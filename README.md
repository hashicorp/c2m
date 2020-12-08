# C2M: HashiCorp Nomad 2 Million Container Challenge

This repository contains all of the code to run scalability tests on Nomad for
the second iteration of the [C1M](https://hashicorp.com/c1m) challenge:

**[C2M](https://hashicorp.com/c2m)**

## Overview

1. Use Packer to build images
2. Use Terraform to provision images
3. Use command and control instance to run `journey`

### C2M Parameters

The following commands were used to provision and run C2M:

```
# From an operators local machine
terraform apply -var cluster_capacity=18000 -var 'nomad_num_schedulers=6' -var 'dd_key=<REDACTED>' -parallelism=20

# From the command and control instance output by terraform
# scp nomad/bench.nomad to command and control instance
# compile journey/ and scp to command and control instance
WORKERS=75 JOBS=2000 JOBSPEC=./bench.nomad PREFIX=c2m- ./journey start
```

## Packer

Required: Packer 1.6+

Packer's HCL2 support is being used, so refer to the [Packer 1.5
docs](https://www.packer.io/docs/from-1.5) for reference.

### Building Images

```sh
cd packer

# Run once per region
packer build -var-file regions/us-west-2.pkrvars.hcl .
```

Run once per region file to build an image per region.

## Terraform

Required: Terraform v0.12+

### Provisioning Infrastructure

To create or update infrastructure:

```sh
cd terraform
terraform init  # On first run only

# The retry_join_tag allows everyone to have their own cluster.
terraform plan -var retry_join_tag="$USER"  
terraform apply -var retry_join_tag="$USER"  

# When you're done
terraform destroy -var retry_join_tag="$USER"
```

## Accessing Cluster

After provisioning infrastructure with Terraform above it may be accessed via a
helper script:


```sh
./nomad.sh status
```

### ssh

Add your ssh key to `terraform/variables.tf` and login as the `admin` user:

```sh
ssh admin@...
```
