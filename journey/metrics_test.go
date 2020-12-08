package main

import (
	"fmt"
	"testing"
	"time"
)

func TestMetrics(t *testing.T) {
	ts := NewTimeseries()

	now := time.Now()

	metrics := []struct {
		time  time.Time
		value float64
	}{
		{
			time:  now.Add(10 * time.Second),
			value: 10.0,
		},
		{
			time:  now.Add(-time.Second),
			value: 5.0,
		},
		{
			time:  now.Add(8 * time.Second),
			value: 8.0,
		},
		{
			time:  now.Add(4 * time.Second),
			value: 4.0,
		},
	}

	for _, m := range metrics {
		ts.Add(m.time, m.value)
	}

	fmt.Println(ts.base)
	fmt.Println(ts.data)
	fmt.Println(ts.BucketBy(5*time.Second, SUM))

}
