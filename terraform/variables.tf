variable "project" {
  default = "nomad-c1m"
}

variable "nomad_server_count" {
  default = 3
}

variable "nomad_server_instance_type" {
  default = "i3.16xlarge"
}

variable "nomad_server_ephemeral_data" {
  default = true
}

variable "nomad_num_schedulers" {
  default = 0
}

variable "consul_server_count" {
  default = 3
}

variable "consul_server_instance_type" {
  default = "t3.large"
}

variable "tls" {
  default = true
}

variable "retry_join_tag" {
  default = "consul"
}

variable "cluster_capacity" {
  type    = number
  default = 16
}

variable "ssh_public_keys" {
  type = list(object({ name : string, key : string }))
  default = [
  ]
}

variable "dd_key" {
  type = string
}
