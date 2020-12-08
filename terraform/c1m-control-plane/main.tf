data "aws_region" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.6"

  name           = var.project
  cidr           = "172.16.0.0/16"
  azs            = var.azs
  public_subnets = var.public_subnets
  //["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  enable_nat_gateway   = false
  enable_dns_hostnames = true
}

module "authorized_keys" {
  source          = "../ssh-public-keys"
  ssh_public_keys = var.ssh_public_keys
}

resource "aws_security_group" "nomad_elb" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 4646
    to_port     = 4646
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "nomad_elb" {
  security_groups = [
    aws_security_group.nomad_elb.id
  ]
  subnets                   = module.vpc.public_subnets
  cross_zone_load_balancing = true
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "TCP:4646"
  }
  listener {
    lb_port           = 4646
    lb_protocol       = "tcp"
    instance_port     = "4646"
    instance_protocol = "tcp"
  }
}

# Our control_plane security group to access
resource "aws_security_group" "control_plane" {
  name        = "control_plane"
  description = "Created using Terraform"
  vpc_id      = module.vpc.vpc_id

  # SSH access from anywhere
  # todo: limit to just bastion
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Nomad ports
  # Allow all traffic to api/ui, auth done via tls
  ingress {
    from_port   = 4646
    to_port     = 4646
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # RPC
  ingress {
    from_port   = 4647
    to_port     = 4647
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Serf
  ingress {
    from_port   = 4648
    to_port     = 4648
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4648
    to_port     = 4648
    protocol    = "udp"
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

data "aws_ami" "cp_ami" {
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
  name   = var.project
}

module "util_asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 3.0"

  name = "c1m-control-${var.project}-util"

  image_id           = data.aws_ami.cp_ami.id
  instance_type = "m5a.large"
  security_groups = [aws_security_group.control_plane.id]

  root_block_device = [{
      volume_size = "100"
      volume_type = "gp2"
    }
  ]


  iam_instance_profile = var.iam_instance_profile_name
  health_check_type         = "EC2"
  key_name                  = module.keypair.key_name
  vpc_zone_identifier       = module.vpc.public_subnets
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  wait_for_capacity_timeout = 0

  user_data_base64 = base64encode(<<EOT
#!/bin/bash

sudo tee /etc/nomad.d/nomad.hcl > /dev/null <<EOC
${templatefile("${path.module}/templates/nomad-util.hcl", { tag_key = var.retry_join_tag})}
EOC

sudo mkdir /etc/nomad.d/tls
sudo tee /etc/nomad.d/tls/ca_cert.pem > /dev/null <<EOC
${var.tls_ca_cert_pem}
EOC
sudo tee /etc/nomad.d/tls/cert.pem > /dev/null <<EOC
${var.tls_server_cert_pem}
EOC
sudo tee /etc/nomad.d/tls/key.pem > /dev/null <<EOC
${var.tls_server_key_pem}
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

sudo tee /home/admin/.ssh/authorized_keys > /dev/null <<EOK
${module.authorized_keys.authorized_keys}
EOK
EOT
  )

  tags = [
    {
      key = "Name"
      value = "C10M Util"
      propagate_at_launch = true
    },
  ]
}

module "control_plane_asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 3.0"

  name = "c1m-control-${var.project}"

  image_id        = data.aws_ami.cp_ami.id
  instance_type   = var.nomad_server_instance_type
  security_groups = [aws_security_group.control_plane.id]

  root_block_device = [
    {
      volume_size = "50"
      volume_type = "gp2"
    },
  ]

  load_balancers = [aws_elb.nomad_elb.id]

  iam_instance_profile = var.iam_instance_profile_name

  # Auto scaling group
  vpc_zone_identifier       = module.vpc.public_subnets
  health_check_type         = "ELB"
  min_size                  = var.nomad_server_count
  max_size                  = var.nomad_server_count
  desired_capacity          = var.nomad_server_count
  wait_for_capacity_timeout = 0
  key_name                  = module.keypair.key_name

  user_data_base64 = base64encode(<<EOT
#!/bin/bash
PUBLIC_IPV4=$(curl -sf "http://169.254.169.254/latest/meta-data/public-ipv4")

DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=${var.dd_key} DD_SITE="datadoghq.com" bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"

sudo tee /etc/nomad.d/nomad.hcl > /dev/null <<EOC

advertise {
  http = "$PUBLIC_IPV4"
  rpc = "$PUBLIC_IPV4"
  serf = "$PUBLIC_IPV4"
}

${templatefile("${path.module}/templates/nomad.hcl",
    {
      datacenter   = "nomad-mgmt"
      cluster_size = var.nomad_server_count
      tag_key      = var.retry_join_tag
      num_schedulers = var.nomad_num_schedulers
})}


EOC


sudo mkdir /etc/nomad.d/tls
sudo tee /etc/nomad.d/tls/ca_cert.pem > /dev/null <<EOC
${var.tls_ca_cert_pem}
EOC
sudo tee /etc/nomad.d/tls/cert.pem > /dev/null <<EOC
${var.tls_server_cert_pem}
EOC
sudo tee /etc/nomad.d/tls/key.pem > /dev/null <<EOC
${var.tls_server_key_pem}
EOC

DEVICE=$(lsblk -do PATH,PTTYPE | grep -v gpt | tail -1 | awk '{print $1}')
sudo mkfs.ext4 $${DEVICE}
sudo mkdir /opt/nomad/data
sudo mount $${DEVICE} /opt/nomad/data

sudo service nomad enable
sudo service nomad start

tee -a /home/admin/.bashrc > /dev/null <<EOC
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_CACERT=/etc/nomad.d/tls/ca_cert.pem
export NOMAD_CLIENT_CERT=/etc/nomad.d/tls/cert.pem
export NOMAD_CLIENT_KEY=/etc/nomad.d/tls/key.pem
export NOMAD_SKIP_VERIFY=1
EOC

sudo tee /home/admin/.ssh/authorized_keys > /dev/null <<EOK
${module.authorized_keys.authorized_keys}
EOK
EOT
)

tags = [
  {
    key                 = var.retry_join_tag
    value               = "auto-join"
    propagate_at_launch = true
  },
]
}




















// module "nomad_workers" {
//   source = "./nomad-client-cluster"

//   project                   = var.project
//   ami_id                    = data.aws_ami.cp_ami.id
//   iam_instance_profile_name = var.iam_instance_profile_name
//   ssh_key_name              = module.keypair.key_name
//   subnet_ids                = module.vpc.private_subnets
//   security_groups           = [aws_security_group.control_plane.id]
//   cluster_capacity          = var.cluster_capacity
//   authorized_keys           = module.authorized_keys.authorized_keys
//   cluster_tag_key           = var.retry_join_tag

//   nomad_region      = data.aws_region.current.name
//   nomad_datacenter  = "workers"
//   consul_datacenter = data.aws_region.current.name

//   enable_tls          = var.enable_tls
//   tls_ca_cert_pem     = var.tls_ca_cert_pem
//   tls_client_cert_pem = var.tls_client_cert_pem
//   tls_client_key_pem  = var.tls_client_key_pem
// }