package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"sort"
	"time"

	"github.com/hashicorp/nomad/api"
	"github.com/hashicorp/nomad/jobspec"

	"github.com/go-echarts/go-echarts/v2/charts"
	"github.com/go-echarts/go-echarts/v2/components"
	"github.com/go-echarts/go-echarts/v2/opts"
)

func collectMetrics(jobFile string, numJobs int, startTime time.Time) (*metrics, error) {
	apiJob, err := jobspec.ParseFile(jobFile)
	if err != nil {
		return nil, fmt.Errorf("failed parsing job file: %v", err)
	}

	count := 0
	for _, tg := range apiJob.TaskGroups {
		count = count + *tg.Count
	}

	metrics := newMetrics(startTime, count)

	// Get the API client
	client, err := api.NewClient(api.DefaultConfig())
	if err != nil {
		return nil, fmt.Errorf("failed creating nomad client: %v", err)
	}

	jobs, _, err := client.Jobs().List(&api.QueryOptions{Prefix: jobPrefix})
	for _, job := range jobs {
		metrics.registered.Add(time.Unix(0, job.SubmitTime), float64(count))
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	errCh := make(chan error, 1)
	allocsCh := make(chan []*api.AllocationListStub, 10)
	tokenCh := make(chan int, 20)
	for _, job := range jobs {
		go func(id string) {
			select {
			case tokenCh <- 1:
			case <-ctx.Done():
				return
			}
			allocs, _, err := client.Jobs().Allocations(id, true, nil)
			if err != nil {
				select {
				case <-ctx.Done():
				case errCh <- fmt.Errorf("failed to get allocations for %q: %w", id, err):
				default:
				}
			}
			select {
			case allocsCh <- allocs:
			case <-ctx.Done():
			}
			select {
			case <-tokenCh:
			case <-ctx.Done():
			}
		}(job.ID)
	}

	// Process task events
	var allocs []*api.AllocationListStub
	for range jobs {
		select {
		case allocs = <-allocsCh:
		case err := <-errCh:
			return nil, err
		}
		for _, alloc := range allocs {
			metrics.placed.Add(time.Unix(0, alloc.CreateTime), 1)
			for _, ts := range alloc.TaskStates {
				for _, event := range ts.Events {
					switch event.Type {
					case api.TaskReceived:
						metrics.received.Add(time.Unix(0, event.Time), 1)
					case api.TaskStarted:
						metrics.running.Add(time.Unix(0, event.Time), 1)
					}
				}
			}
		}
	}

	return metrics, nil
}

type metrics struct {
	registered *Timeseries
	placed     *Timeseries
	received   *Timeseries
	running    *Timeseries
}

func (m *metrics) Graph() error {
	registered := m.registered.BucketBy(time.Second, COUNT)
	placed := m.placed.BucketBy(time.Second, COUNT)
	received := m.received.BucketBy(time.Second, COUNT)
	running := m.running.BucketBy(time.Second, COUNT)

	line := charts.NewLine()
	line.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title: "Results",
		}),
		charts.WithTooltipOpts(opts.Tooltip{
			Show:    true,
			Trigger: "axis",
		}),
		charts.WithInitializationOpts(opts.Initialization{
			PageTitle: "Nomad Benchmark Results",
			Theme:     "shine",
		}),
		charts.WithLegendOpts(opts.Legend{Show: true}),
		charts.WithYAxisOpts(opts.YAxis{
			Name: "Allocations",
			Type: "value",
		}),
		charts.WithXAxisOpts(opts.XAxis{
			Name: "Time",
			Type: "time",
		}),
	)

	line.SetXAxis(xAxis(len(running))).
		AddSeries("Registered", convertLineData(registered, m.registered.baseTime, time.Second)).
		AddSeries("Placed", convertLineData(placed, m.placed.baseTime, time.Second)).
		AddSeries("Received", convertLineData(received, m.received.baseTime, time.Second)).
		AddSeries("Running", convertLineData(running, m.running.baseTime, time.Second))

	page := components.NewPage()
	page.AddCharts(line)

	f, err := os.Create("results.html")
	if err != nil {
		return err
	}

	data, err := json.Marshal(&MetricsJSON{
		StartTime:  m.running.baseTime,
		Registered: registered,
		Placed:     placed,
		Received:   received,
		Running:    running,
	})

	if err := ioutil.WriteFile("raw.json", data, 0644); err != nil {
		return err
	}

	return page.Render(io.MultiWriter(f))
}

type MetricsJSON struct {
	StartTime  time.Time `json:"start_time"`
	Registered []float64 `json:"registered"`
	Placed     []float64 `json:"placed"`
	Received   []float64 `json:"received"`
	Running    []float64 `json:"running"`
}

func xAxis(l int) []uint32 {
	v := make([]uint32, l)
	for idx := range v {
		v[idx] = uint32(idx + 1)
	}
	return v
}

func convertLineData(d []float64, base time.Time, interval time.Duration) []opts.LineData {
	data := make([]opts.LineData, len(d))
	for idx := range d {
		data[idx] = opts.LineData{Value: []interface{}{base.Add(time.Duration(idx+1) * interval), d[idx]}, Symbol: "none"}
	}
	return append([]opts.LineData{{Value: []interface{}{base, 0.0}, Symbol: "none"}}, data...)
}

func newMetrics(t time.Time, sizeHint int) *metrics {
	return &metrics{
		registered: NewTimeseriesWithBase(t, sizeHint),
		placed:     NewTimeseriesWithBase(t, sizeHint),
		received:   NewTimeseriesWithBase(t, sizeHint),
		running:    NewTimeseriesWithBase(t, sizeHint),
	}
}

type Timeseries struct {
	sorted   bool
	baseTime time.Time
	baseNano int64
	data     []datapoint
}

func NewTimeseriesWithBase(base time.Time, sizeHint int) *Timeseries {
	return &Timeseries{
		baseTime: base,
		baseNano: base.UnixNano(),
		data:     make([]datapoint, 0, sizeHint),
	}
}

type datapoint struct {
	time  int32 // offset from base
	value float64
}

// Add appends a new timestamp and adjusts the base time as needed.
func (t *Timeseries) Add(at time.Time, val float64) {
	t.sorted = false
	offset := (at.UnixNano() - t.baseNano) / int64(time.Millisecond)
	t.data = append(t.data, datapoint{time: int32(offset), value: val})
}

func (t *Timeseries) AddNow(val float64) {
	t.Add(time.Now(), val)
}

// BucketBy buckets timeseries and sorts them if needed.
func (t *Timeseries) BucketBy(d time.Duration, agg Aggregator) []float64 {
	if !t.sorted {
		sort.Slice(t.data, func(i, j int) bool { return t.data[i].time < t.data[j].time })
		t.sorted = true
	}
	if d < time.Second {
		d = time.Second
	}
	size := int32(d / time.Millisecond)
	prev := 0.0
	bucket := []float64{}
	series := []float64{}
	seriesIdx := int32(1)
	for idx := range t.data {
		if t.data[idx].time < (seriesIdx * size) {
			bucket = append(bucket, t.data[idx].value)
		} else {
			//flush bucket
			prev = agg(bucket, prev)
			series = append(series, prev)
			seriesIdx++
			bucket = append([]float64{}, t.data[idx].value)
			for t.data[idx].time >= (seriesIdx)*size {
				series = append(series, prev)
				seriesIdx++
			}
			// goto next incrememnts
		}
	}
	// flush last bucket
	prev = agg(bucket, prev)
	series = append(series, prev)

	return series
}

type Aggregator func([]float64, float64) float64

func SUM(vals []float64, _ float64) (v float64) {
	for _, f := range vals {
		v += f
	}
	return
}

func COUNT(vals []float64, prev float64) (v float64) {
	return SUM(vals, prev) + prev
}
