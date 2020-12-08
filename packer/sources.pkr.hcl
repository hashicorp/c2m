locals {
    timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "nomad-c1m" {
    region = var.aws_region
    source_ami = var.aws_source_ami
    instance_type = var.aws_instance_type
    ssh_username = var.ssh_username
    ami_name = "nomad-c1m-${local.timestamp}"
}
