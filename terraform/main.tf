resource "random_pet" "c1m" {}

# Create an IAM role for the auto-join
resource "aws_iam_role" "nomad-c1m" {
  name = "nomad-c1m-${random_pet.c1m.id}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Create an IAM policy for allowing instances that are running
# Consul agent can use to list the consul servers.
resource "aws_iam_policy" "nomad-c1m" {
  name        = "nomad-c1m-${random_pet.c1m.id}"
  description = "Allows nodes to describe instances for joining."

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action":"s3:GetObject",
      "Resource": "arn:aws:s3:::nomad-c1m/*"
    }
  ]
}
EOF
}

# Attach the policy
resource "aws_iam_policy_attachment" "nomad-c1m" {
  name       = "nomad-c1m-${random_pet.c1m.id}"
  roles      = ["${aws_iam_role.nomad-c1m.name}"]
  policy_arn = aws_iam_policy.nomad-c1m.arn
}

resource "aws_iam_policy_attachment" "nomad-c1m-ssm" {
  name       = "nomad-c1m-${random_pet.c1m.id}-ssm"
  roles      = ["${aws_iam_role.nomad-c1m.name}"]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create the instance profile
resource "aws_iam_instance_profile" "nomad-c1m" {
  name = "nomad-c1m-${random_pet.c1m.id}"
  role = aws_iam_role.nomad-c1m.name
}

resource "tls_private_key" "ca_key" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "ca_cert" {
  key_algorithm   = "RSA"
  private_key_pem = tls_private_key.ca_key.private_key_pem

  subject {
    common_name  = "nomad-c1m"
    organization = "HashiCorp Nomad"
  }

  validity_period_hours = 12

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
    "cert_signing"
  ]

  is_ca_certificate = true
}

resource "tls_private_key" "server_key" {
  algorithm = "RSA"
}

resource "tls_cert_request" "server_csr" {
  key_algorithm   = "RSA"
  private_key_pem = tls_private_key.server_key.private_key_pem

  subject {
    common_name  = "server.nomad-c1m"
    organization = "HashiCorp Nomad"
  }
}

resource "tls_locally_signed_cert" "server_cert" {
  cert_request_pem   = tls_cert_request.server_csr.cert_request_pem
  ca_key_algorithm   = "RSA"
  ca_private_key_pem = tls_private_key.ca_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca_cert.cert_pem

  validity_period_hours = 12

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]
}

resource "tls_private_key" "client_key" {
  algorithm = "RSA"
}

resource "tls_cert_request" "client_csr" {
  key_algorithm   = "RSA"
  private_key_pem = tls_private_key.client_key.private_key_pem

  subject {
    common_name  = "client.nomad-c1m"
    organization = "HashiCorp Nomad"
  }
}

resource "tls_locally_signed_cert" "client_cert" {
  cert_request_pem   = tls_cert_request.client_csr.cert_request_pem
  ca_key_algorithm   = "RSA"
  ca_private_key_pem = tls_private_key.ca_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca_cert.cert_pem

  validity_period_hours = 12

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]
}

module "nomad-c1m_us-east-1" {
  source = "./c1m-control-plane"

  project                    = "c1m-${random_pet.c1m.id}"
  azs                        = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets             = ["172.16.0.0/24", "172.16.1.0/24", "172.16.2.0/24"]
  nomad_server_count         = var.nomad_server_count
  nomad_server_instance_type = var.nomad_server_instance_type
  iam_instance_profile_name  = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys            = var.ssh_public_keys
  tls_ca_cert_pem            = tls_self_signed_cert.ca_cert.cert_pem
  tls_server_cert_pem        = tls_locally_signed_cert.server_cert.cert_pem
  tls_server_key_pem         = tls_private_key.server_key.private_key_pem
  retry_join_tag             = var.retry_join_tag
  dd_key                     = var.dd_key

  providers = {
    aws = aws.us-east-1
  }
}

module "client-cluster_ca-central-1" {
  source = "./nomad-client-cluster"

  project         = "c1m-${random_pet.c1m.id}"
  azs             = ["ca-central-1a", "ca-central-1b", "ca-central-1d"]
  private_subnets = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20"]
  public_subnets  = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "ca-central-1"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.ca-central-1
  }
}

module "client-cluster_us-east-1" {
  source = "./nomad-client-cluster"

  project         = "c1m-${random_pet.c1m.id}"
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"]
  private_subnets = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20", "172.16.48.0/20", "172.16.64.0/20", "172.16.80.0/20"]
  public_subnets  = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20", "172.16.176.0/20", "172.16.192.0/20", "172.16.208.0/24"]
  #azs     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  #private_subnets = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20"]
  #public_subnets = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "us-east-1"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.us-east-1
  }
}

module "client-cluster_us-east-2" {
  source = "./nomad-client-cluster"

  project         = "c1m-${random_pet.c1m.id}"
  azs             = ["us-east-2a", "us-east-2b", "us-east-2c"]
  private_subnets = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20"]
  public_subnets  = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "us-east-2"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.us-east-2
  }
}

module "client-cluster_us-west-2" {
  source = "./nomad-client-cluster"

  project                   = "c1m-${random_pet.c1m.id}"
  azs                       = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets           = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20"]
  public_subnets            = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "us-west-2"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.us-west-2
  }
}

module "client-cluster_us-west-1" {
  source = "./nomad-client-cluster"

  project                   = "c1m-${random_pet.c1m.id}"
  azs                       = ["us-west-1a", "us-west-1b"]
  private_subnets           = ["172.16.0.0/20", "172.16.16.0/20"]
  public_subnets            = ["172.16.128.0/20", "172.16.144.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "us-west-1"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.us-west-1
  }
}

module "client-cluster_eu-west-1" {
  source = "./nomad-client-cluster"

  project                   = "c1m-${random_pet.c1m.id}"
  azs                       = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets           = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20"]
  public_subnets            = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "eu-west-1"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.eu-west-1
  }
}

module "client-cluster_eu-west-2" {
  source = "./nomad-client-cluster"

  project                   = "c1m-${random_pet.c1m.id}"
  azs                       = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  private_subnets           = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20"]
  public_subnets            = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "eu-west-2"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.eu-west-2
  }
}

module "client-cluster_eu-west-3" {
  source = "./nomad-client-cluster"

  project                   = "c1m-${random_pet.c1m.id}"
  azs                       = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
  private_subnets           = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20"]
  public_subnets            = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "eu-west-3"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.eu-west-3
  }
}

module "client-cluster_eu-central-1" {
  source = "./nomad-client-cluster"

  project                   = "c1m-${random_pet.c1m.id}"
  azs                       = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets           = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20"]
  public_subnets            = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "eu-central-1"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.eu-central-1
  }
}

module "client-cluster_ap-southeast-1" {
  source = "./nomad-client-cluster"

  project                   = "c1m-${random_pet.c1m.id}"
  azs                       = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
  private_subnets           = ["172.16.0.0/20", "172.16.16.0/20", "172.16.32.0/20"]
  public_subnets            = ["172.16.128.0/20", "172.16.144.0/20", "172.16.160.0/20"]
  cluster_capacity          = var.cluster_capacity
  iam_instance_profile_name = aws_iam_instance_profile.nomad-c1m.name
  ssh_public_keys           = var.ssh_public_keys
  tls_ca_cert_pem           = tls_self_signed_cert.ca_cert.cert_pem
  tls_client_cert_pem       = tls_locally_signed_cert.client_cert.cert_pem
  tls_client_key_pem        = tls_private_key.client_key.private_key_pem

  nomad_datacenter = "ap-southeast-1"
  retry_join_tag   = var.retry_join_tag

  dd_key = var.dd_key

  providers = {
    aws = aws.ap-southeast-1
  }
}

resource "local_file" "nomad-ca-cert" {
  filename        = "${path.module}/certs/ca.crt"
  content         = tls_self_signed_cert.ca_cert.cert_pem
  file_permission = "0600"
}

resource "local_file" "nomad-cert" {
  filename        = "${path.module}/certs/nomad.crt"
  content         = tls_locally_signed_cert.client_cert.cert_pem
  file_permission = "0600"
}

resource "local_file" "nomad-key" {
  filename        = "${path.module}/certs/nomad.key"
  content         = tls_private_key.client_key.private_key_pem
  file_permission = "0600"
}

resource "local_file" "nomad-sh" {
  filename = "${path.module}/nomad.sh"
  content  = <<EOF
#!/bin/bash
NOMAD_ADDR=https://${module.nomad-c1m_us-east-1.nomad_addr} NOMAD_CACERT=${path.module}/certs/ca.crt NOMAD_CLIENT_CERT=${path.module}/certs/nomad.crt NOMAD_CLIENT_KEY=${path.module}/certs/nomad.key NOMAD_SKIP_VERIFY=1 nomad $@
EOF
}
