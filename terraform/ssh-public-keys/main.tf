variable "ssh_public_keys" {
  description = "List of extra ssh public keys to be added to the instances"
  type        = list(object({ name : string, key : string }))
  default     = []
}

variable "user" {
  type    = string
  default = "admin"
}

data "template_file" "authorized_keys" {
  template = <<EOF
%{for k in var.ssh_public_keys~}
# ${k.name}
${k.key}
%{endfor~}
EOF
}

output "authorized_keys" {
  value = data.template_file.authorized_keys.rendered
}