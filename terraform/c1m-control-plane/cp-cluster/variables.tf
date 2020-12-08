variable "project" {
  description = "The name of the cluster. This variable is used to namespace all resources created by this module."
  type        = string
}

variable "ami_id" {
  description = "The ID of the AMI to run in this cluster. Should be an AMI that had Nomad and Consul installed."
  type        = string
}

variable "iam_instance_profile_name" {
  description = "The name of the IAM instance profile to attach"
  type        = string
}

variable "ssh_key_name" {
  description = "The AWS key pair name to use with the created instances."
  type        = string
}

variable "instance_type" {
  description = "The type of EC2 Instances to run for each node in the cluster (e.g. t2.micro)."
  type        = string
}

variable "cluster_size" {
  description = "The number of nodes to have in the cluster. Should be 3 or 5"
  type        = number
  default     = 3
}

variable "cluster_tag_key" {
  description = "Add a tag with this key and the value var.cluster_tag_value to each Instance in the ASG. This can be used to automatically find other Consul nodes and form a cluster."
  type        = string
  default     = "consul"
}

variable "cluster_tag_value" {
  description = "Add a tag with key var.clsuter_tag_key and this value to each Instance in the ASG. This can be used to automatically find other Consul nodes and form a cluster."
  type        = string
  default     = "auto-join"
}

variable "subnet_ids" {
  description = "The subnet IDs into which the EC2 Instances should be deployed. We recommend one subnet ID per node in the cluster_size variable."
  type        = list(string)
  default     = null
}

variable "security_groups" {
  type = list(string)
}

variable "authorized_keys" {
  description = "Body of the authorized keys file."
  type        = string
  default     = null
}

variable "tags" {
  description = "List of extra tag blocks added to the autoscaling group configuration. Each element in the list is a map containing keys 'key', 'value', and 'propagate_at_launch' mapped to the respective values."
  type        = list(object({ key : string, value : string, propagate_at_launch : bool }))
  default     = []
}

variable "nomad_server" {
  description = "Toggles if Nomad should be configured in server mode"
  type        = bool
  default     = true
}

variable "nomad_client" {
  description = "Toggles if Nomad should be configured in client mode"
  type        = bool
  default     = true
}

variable "consul_server" {
  description = "Toggles if Consul should be configured in server mode"
  type        = bool
  default     = true
}

variable "nomad_region" {
  type    = string
  default = "global"
}

variable "nomad_datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_datacenter" {
  type    = string
  default = "global"
}

variable "enable_tls" {
  type    = bool
  default = false
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

variable "tls_server_cert_pem" {
  type    = string
  default = ""
}

variable "tls_server_key_pem" {
  type    = string
  default = ""
}

variable "elb_ids" {
  type = list(string)
}

variable "ephemeral_storage" {
  type    = bool
  default = false
}

variable "dd_key" {
  type    = string
  default = ""
}