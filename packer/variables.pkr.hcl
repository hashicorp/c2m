variable "aws_region" {
    type = string
    description = "The AWS region to build the AMI for."
}

variable "aws_source_ami" {
    type = string
    description = "The source AMI to build from."
}

variable "aws_instance_type" {
    type = string
    default = "t2.medium"
    description = "The AWS instance type to use for the build"
}

variable "ssh_username" {
    type = string
    default = "admin"
    description = "The user to use for SSH during provisioning"
}

variable "aws_iam_instance_profile" {
    type = string
    default = "packer_build"
    description = "The AWS IAM instance profile to use during provisioning"
}

