#!/bin/bash

timestamp=$(date +%s)
for region in ap-southeast-1 ca-central-1 eu-central-1 eu-west-1 eu-west-2 eu-west-3 us-east-1 us-east-2 us-west-1 us-west-2; do
    echo "==> Dumping $region @ $timestamp"
    aws --region $region ec2 describe-instances --filters Name=instance-state-name,Values=running | jq -r '.Reservations[].Instances[] | .InstanceType + "," + .Placement.AvailabilityZone' > "$timestamp-$region.csv"
done
