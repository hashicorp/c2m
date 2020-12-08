package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/hashicorp/nomad/api"
	"github.com/hashicorp/nomad/jobspec"
	"github.com/mitchellh/copystructure"
	"github.com/mitchellh/go-glint"
)

const (
	// pollInterval is how often the status command will poll for results.
	pollInterval = 2 * time.Second

	maxWait = 30 * time.Minute

	// blockedEvalTries is how many times we will wait for a blocked eval to
	// complete before moving on.
	blockedEvalTries = 5

	// pendingAllocTries is how many times we will wait for a pending alloc to
	// complete before moving on.
	pendingAllocTries = 5
)

var numJobs, totalProcs int
var jobFile string

var jobSubmitters = 20

var jobPrefix = "c1b-"

func main() {

	// Get the number of jobs to submit
	var err error
	v := os.Getenv("JOBS")
	if numJobs, err = strconv.Atoi(v); err != nil {
		log.Fatalln("[ERR] nomad: JOBS must be numeric")
	}

	// Get the location of the job file
	if jobFile = os.Getenv("JOBSPEC"); jobFile == "" {
		log.Fatalln("[ERR] nomad: JOBSPEC must be provided")
	}

	if workers, err := strconv.Atoi(os.Getenv("WORKERS")); err == nil {
		jobSubmitters = workers
	}

	if prefix := os.Getenv("PREFIX"); prefix != "" {
		jobPrefix = prefix
	}

	if len(os.Args) < 2 {
		log.Fatalln("must specify start or stop arg")
	}

	if url, err := serve(); err != nil {
		log.Fatalf("[ERR] nomad: error starting http server: %v", err)
	} else {
		log.Printf("[DEBUG] nomad: http server started at: %s", url)
	}

	switch os.Args[1] {
	case "stop":
		stop()
	case "start":
		d := glint.New()
		go d.Render(context.Background())
		startTime := start(jobFile, numJobs, d)
		graphMetrics(jobFile, numJobs, startTime)
	case "metrics":
		if len(os.Args) < 3 {
			log.Fatalln("must specify start time as RFC3339Nano or Unix seconds")
		}
		startTime, err := time.Parse(time.RFC3339Nano, os.Args[2])
		if err != nil {
			nanos, err2 := strconv.ParseInt(os.Args[2], 10, 64)
			if err2 != nil {
				log.Fatalf("unable to parse start time as RFC3339Nano or Unix:\n"+
					"RFC3339Nano : %v\n"+
					"Unix Seconds: %v\n", err, err2,
				)
			}
			startTime = time.Unix(nanos, 0)
		}
		graphMetrics(jobFile, numJobs, startTime)
	}
}

func stop() {
	// Get the API client
	client, err := api.NewClient(api.DefaultConfig())
	if err != nil {
		log.Fatalf("[ERR] nomad: failed creating nomad client: %v", err)
	}

	// Iterate all of the jobs and stop them
	log.Printf("[DEBUG] nomad: deregistering benchmark jobs")
	jobs, _, err := client.Jobs().PrefixList(jobPrefix)
	if err != nil {
		log.Fatalf("[ERR] nomad: failed listing jobs: %v", err)
	}

	if len(jobs) < jobSubmitters {
		jobSubmitters = len(jobs)
	}
	log.Printf("[DEBUG] nomad: using %d parallel job submitters", jobSubmitters)

	// Submit the job the requested number of times
	errCh := make(chan error, len(jobs))
	stopCh := make(chan struct{})
	jobsCh := make(chan string, jobSubmitters)
	defer close(stopCh)
	for i := 0; i < jobSubmitters; i++ {
		go deregJobs(client.Jobs(), jobsCh, stopCh, errCh)
	}

	for _, job := range jobs {
		jobsCh <- job.ID
	}

	// Collect errors if any
	for range jobs {
		select {
		case err := <-errCh:
			if err != nil {
				log.Fatalf("[ERR] nomad: failed deregistering job: %v", err)
			}
		case <-stopCh:
			return
		}
	}

	//client.System().GarbageCollect()
}

func deregJobs(client *api.Jobs, jobs <-chan string, stopCh chan struct{}, errCh chan<- error) {
	for {
		select {
		case jobID := <-jobs:
			_, _, err := client.Deregister(jobID, false, nil)
			errCh <- err
		case <-stopCh:
			return
		}
	}
}

// start the job, block until completion, and return the started time
func start(jobFile string, numJobs int, d *glint.Document) time.Time {
	// Parse the job file
	apiJob, err := jobspec.ParseFile(jobFile)
	if err != nil {
		log.Fatalf("[ERR] nomad: failed parsing job file: %v", err)
	}

	jobID := *apiJob.ID
	jobID = jobPrefix + jobID

	// Get the API client
	client, err := api.NewClient(api.DefaultConfig())
	if err != nil {
		log.Fatalf("[ERR] nomad: failed creating nomad client: %v", err)
	}

	if numJobs < jobSubmitters {
		jobSubmitters = numJobs
	}
	log.Printf("[DEBUG] nomad: using %d parallel job submitters", jobSubmitters)
	var totalAllocs int
	for _, tg := range apiJob.TaskGroups {
		totalAllocs += *tg.Count
	}

	totalAllocs = totalAllocs * numJobs
	log.Printf("[DEBUG] nomad: computed target of %d allocations", totalAllocs)

	// Submit the job the requested number of times
	stopCh := make(chan struct{})
	jobsCh := make(chan *api.Job)
	defer close(stopCh)
	for i := 0; i < jobSubmitters; i++ {
		worker := newJobWorker(client)
		go worker.run(jobsCh, stopCh)
	}

	log.Printf("[DEBUG] nomad: submitting %d jobs", numJobs)
	startTime := time.Now()
	log.Printf("Started at: %s (%d)", startTime.Format(time.RFC3339Nano), startTime.Unix())
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	watcher := newJobSumWatcher(client, startTime, totalAllocs, jobPrefix)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		watcher.run(ctx)
		wg.Done()
	}()
	d.Append(watcher)
	for i := 0; i < numJobs; i++ {
		copy, err := copystructure.Copy(apiJob)
		if err != nil {
			log.Fatalf("[ERR] nomad: failed to copy api job: %v", err)
		}

		// Increment the job ID
		jobCopy := copy.(*api.Job)
		newID := fmt.Sprintf("%s-%d", jobID, i)
		jobCopy.ID = &newID
		jobCopy.Name = &newID
		jobsCh <- jobCopy
	}

	wg.Wait()

	for i := 0; i < jobSubmitters; i++ {
		stopCh <- struct{}{}
	}
	d.Close()
	return startTime
}

func graphMetrics(jobFile string, numJobs int, startTime time.Time) {
	log.Printf("[DEBUG] nomad: collecting metrics")
	metrics, err := collectMetrics(jobFile, numJobs, startTime)
	if err != nil {
		log.Fatalf("[ERR] nomad: failed to retrieve metrics: %v", err)
	} else {
		log.Printf("[DEBUG] nomad: graphing metrics")
		metrics.Graph()
		log.Printf("[DEBUG] nomad: metrics collected and graphed successfully")
	}
}

type jobWorker struct {
	client *api.Client
}

func newJobWorker(client *api.Client) *jobWorker {
	return &jobWorker{
		client: client,
	}
}

func (w *jobWorker) run(jobs <-chan *api.Job, stopCh chan struct{}) {
	for {
		select {
		case job := <-jobs:
			if err := w.processJob(job); err != nil {
				log.Printf("[ERROR] nomad: failed to process job %q: %v", *job.Name, err)
			}
		case <-stopCh:
			return
		}
	}
}

func (w *jobWorker) processJob(job *api.Job) error {
	_, _, err := w.client.Jobs().Register(job, nil)
	return err
}
