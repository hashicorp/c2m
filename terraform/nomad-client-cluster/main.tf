module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.6"

  name                 = var.project
  cidr                 = "172.16.0.0/16"
  azs                  = var.azs
  private_subnets      = var.private_subnets
  public_subnets       = var.public_subnets
  enable_nat_gateway   = true
  enable_dns_hostnames = true
}

module "authorized_keys" {
  source          = "../ssh-public-keys"
  ssh_public_keys = var.ssh_public_keys
}

# Our control_plane security group to access
resource "aws_security_group" "cluster" {
  name        = "cluster"
  vpc_id      = module.vpc.vpc_id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = "true"
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

data "aws_ami" "cluster_ami" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["nomad-c1m-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

module "keypair" {
  source = "mitchellh/dynamic-keys/aws"
  name   = "${var.project}-clients"
}

resource "aws_launch_template" "nomad_client" {
  name = "nomad-c1m-client-${var.project}"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      volume_size           = 50
      volume_type           = "gp2"
    }
  }

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  image_id               = data.aws_ami.cluster_ami.id
  vpc_security_group_ids = [aws_security_group.cluster.id]

  key_name = module.keypair.key_name

  user_data = base64encode(<<EOT
#!/bin/bash

# Random seed used to install datadog and nomad telemetry on a sample of clients
# RANDOM is a builtin bash variable which generates a random uint16, checking that it is
# less that 327 yield about a %1 sample size.
SEED=$RANDOM
FLOOR=327

sudo tee /etc/nomad.d/nomad.hcl > /dev/null <<EOC
${templatefile("${path.module}/templates/nomad.hcl",
    {
      datacenter = var.nomad_datacenter
      cp_region = var.cp_region
      tag_key      = var.retry_join_tag
})}
EOC

if [ "$SEED" -le $FLOOR ]; then
  DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=${var.dd_key} DD_SITE="datadoghq.com" bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
  sudo tee /etc/nomad.d/telem.hcl > /dev/null <<EOC
telemetry {
  datadog_address = "127.0.0.1:8125"
  collection_interval        = "1s"
  disable_hostname           = true
  prometheus_metrics         = true
  publish_allocation_metrics = true
  publish_node_metrics       = true
}
EOC
fi

sudo mkdir /etc/nomad.d/tls
sudo tee /etc/nomad.d/tls/ca_cert.pem > /dev/null <<EOC
${var.tls_ca_cert_pem}
EOC
sudo tee /etc/nomad.d/tls/cert.pem > /dev/null <<EOC
${var.tls_client_cert_pem}
EOC
sudo tee /etc/nomad.d/tls/key.pem > /dev/null <<EOC
${var.tls_client_key_pem}
EOC

sudo service nomad enable
sudo service nomad start

tee -a /home/admin/.bashrc > /dev/null <<EOC
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_CACERT=/etc/nomad.d/tls/ca_cert.pem
export NOMAD_CLIENT_CERT=/etc/nomad.d/tls/cert.pem
export NOMAD_CLIENT_KEY=/etc/nomad.d/tls/key.pem
export NOMAD_SKIP_VERIFY=1
EOC

sudo sysctl -w kernel.pid_max=500000

sudo tee /home/admin/.ssh/authorized_keys > /dev/null <<EOK
${module.authorized_keys.authorized_keys}
EOK
EOT
)
}

resource "aws_autoscaling_group" "example" {
  max_size = var.cluster_capacity
  min_size = var.cluster_capacity

  vpc_zone_identifier       = module.vpc.private_subnets
  wait_for_capacity_timeout = 0
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  mixed_instances_policy {
    instances_distribution {
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "capacity-optimized"
    }
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.nomad_client.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = var.instance_weights
        content {
          instance_type     = override.key
          weighted_capacity = override.value
        }
      }
    }
  }
}
