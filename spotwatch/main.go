package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/ec2metadata"
	"github.com/aws/aws-sdk-go/aws/session"
	cleanhttp "github.com/hashicorp/go-cleanhttp"
	hclog "github.com/hashicorp/go-hclog"
	"github.com/hashicorp/nomad/api"
)

const (
	key = "spot/instance-action"
)

func main() {
	logger := hclog.Default()
	logger.Info("creating ec2 metadata client")
	ec2meta, err := ec2MetaClient("", time.Second)
	if err != nil {
		logger.Error("failed to build metadata client", "error", err)
		os.Exit(1)
	}

	nomad, err := api.NewClient(api.DefaultConfig())
	if err != nil {
		logger.Error("failed to build nomad client", "error", err)
		os.Exit(1)
	}

	nodeID, err := getLocalNodeID(nomad)
	if err != nil {
		logger.Error("failed to get local nomad node ID", "error", err)
		os.Exit(1)
	}

	logger.Info("starting termination watch")
	for {
		time.Sleep(time.Second)
		resp, _ := ec2meta.GetMetadata(key)
		if strings.TrimSpace(resp) == "" {
			// do nothing
			continue
		}

		//check action
		var action spotInstanceAction
		if err = json.Unmarshal([]byte(resp), &action); err != nil {
			logger.Warn("failed to decode action", "error", err)
			continue
		}

		fmt.Println(action)
		if action.Action == "terminate" {
			deadline := action.Time.Sub(time.Now()) - (10 * time.Second)
			logger.Info("termination action detected, draining node", "deadline", deadline, "nodeID", nodeID)
			spec := &api.DrainSpec{
				Deadline: deadline,
			}
			_, err := nomad.Nodes().UpdateDrain(nodeID, spec, false, nil)
			if err != nil {
				logger.Warn("failed to enable nomad node drain", "nodeID", nodeID, "error", err)
				continue
			}

			os.Exit(0)
		}
	}
}

type spotInstanceAction struct {
	Action string    `json:"action"`
	Time   time.Time `json:"time"`
}

func ec2MetaClient(endpoint string, timeout time.Duration) (*ec2metadata.EC2Metadata, error) {
	client := &http.Client{
		Timeout:   timeout,
		Transport: cleanhttp.DefaultTransport(),
	}

	c := aws.NewConfig().WithHTTPClient(client).WithMaxRetries(0)
	if endpoint != "" {
		c = c.WithEndpoint(endpoint)
	}

	fmt.Println(c.Endpoint)

	sess, err := session.NewSession(c)
	if err != nil {
		return nil, err
	}
	return ec2metadata.New(sess, c), nil
}

// getLocalNodeID returns the node ID of the local Nomad Client and an error if
// it couldn't be determined or the Agent is not running in Client mode.
func getLocalNodeID(client *api.Client) (string, error) {
	info, err := client.Agent().Self()
	if err != nil {
		return "", fmt.Errorf("Error querying agent info: %s", err)
	}
	clientStats, ok := info.Stats["client"]
	if !ok {
		return "", fmt.Errorf("Nomad not running in client mode")
	}

	nodeID, ok := clientStats["node_id"]
	if !ok {
		return "", fmt.Errorf("Failed to determine node ID")
	}

	return nodeID, nil
}
