variable "project" {
  default = "nomad-c1m"
}

variable "nomad_server_count" {
  default = 3
}

variable "nomad_server_instance_type" {
  type    = string
  default = "t3.small"
}

variable "nomad_num_schedulers" {
  default = 0
}

variable "retry_join_tag" {
  type    = string
  default = "nomad"
}

variable "iam_instance_profile_name" {
  type = string
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

variable "tls_server_cert_pem" {
  type    = string
  default = ""
}

variable "tls_server_key_pem" {
  type    = string
  default = ""
}

variable "azs" {
  type = list(string)
}

variable "public_subnets" {
  type = list(string)
}

variable "dd_key" {
  type    = string
  default = ""
}