output "nomad_addr" {
  value = "${aws_elb.nomad_elb.dns_name}:4646"
}
