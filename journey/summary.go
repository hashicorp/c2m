package main

import (
	"context"
	"sync"
	"time"

	"github.com/hashicorp/nomad/api"
	"github.com/mitchellh/go-glint"
	"github.com/mitchellh/go-glint/components"
)

type jobSummaryWatcher struct {
	client        *api.Client
	jobPrefix     string
	totalQueued   int
	totalStarting int
	totalRunning  int
	totalComplete int
	totalFailed   int
	totalLost     int
	err           error
	m             sync.Mutex

	watch *components.StopwatchComponent
	pb    *components.ProgressElement
}

func newJobSumWatcher(client *api.Client, startTime time.Time, totalAllocs int, jobPrefix string) *jobSummaryWatcher {
	return &jobSummaryWatcher{
		client:    client,
		jobPrefix: jobPrefix,
		watch:     components.Stopwatch(startTime),
		pb:        components.Progress(totalAllocs),
	}
}

func (w *jobSummaryWatcher) run(ctx context.Context) {
	for {
		select {
		case <-time.After(2 * time.Second):
			jobs, _, err := w.client.Jobs().List(&api.QueryOptions{Prefix: w.jobPrefix})
			if err != nil {
				w.err = err
				break
			}

			var running int

			for _, job := range jobs {
				for _, sum := range job.JobSummary.Summary {
					running += sum.Running
				}
			}

			w.m.Lock()
			w.totalRunning = running
			w.pb.SetCurrent(int64(running))
			w.m.Unlock()

			if int64(running) >= w.pb.Total() {
				return
			}
		case <-ctx.Done():
			return
		}
	}
}

func (w *jobSummaryWatcher) Body(ctx context.Context) glint.Component {
	w.m.Lock()
	defer w.m.Unlock()

	color := glint.Color("green")
	if w.err != nil {
		color = glint.Color("red")
	}

	return glint.Style(
		glint.Layout(w.watch, w.pb),
		color,
	)
}
