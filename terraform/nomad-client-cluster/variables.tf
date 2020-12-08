variable "project" {
  description = "The name of the cluster. This variable is used to namespace all resources created by this module."
  type        = string
}

variable "iam_instance_profile_name" {
  description = "The name of the IAM instance profile to attach"
  type        = string
}

variable "nomad_datacenter" {
  type = string
}

variable "cp_region" {
  type = string
  default =  "us-east-1"
}

variable "cluster_capacity" {
  description = "The capacity of the cluster. Capacity units are weighted as 1 = 4GB"
  type        = number
  default     = 2
}

variable "retry_join_tag" {
  type    = string
  default = "nomad"
}

variable "ssh_public_keys" {
  description = "List of extra ssh public keys to be added to the instances"
  type        = list(object({ name : string, key : string }))
  default     = []
}

variable "tls_ca_cert_pem" {
  type    = string
  default = ""
}

variable "tls_client_cert_pem" {
  type    = string
  default = ""
}

variable "tls_client_key_pem" {
  type    = string
  default = ""
}

variable "azs" {
  type = list(string)
}

variable "public_subnets" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

variable "instance_weights" {
  type = map
  default = {
    "m4.xlarge": "16",
    "m5.xlarge": "16",
    "m5a.xlarge": "16",
    "t3.xlarge": "16",
    "t3a.xlarge": "16",

    "m4.2xlarge": "32"
    "m5.2xlarge": "32",
    "m5a.2xlarge": "32",
    "t3.2xlarge": "32",
    "t3a.2xlarge": "32",

    "m4.4xlarge": "64"
    "m5.4xlarge": "64",
    "m5a.4xlarge": "64",
  }
}

variable "dd_key" {
  type = string
}