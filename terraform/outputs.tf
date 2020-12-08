/*output "consul_server_ips" {
  value = "${module.consul_server.consul_server_ips}"
}*/

output "message" {
  value = <<EOM
Your cluster has been provisioned! TLS certificates have been placed in the 'certs' directory.
Use the generated nomad.sh file to preconfigure your nomad client:

  ./nomad.sh status

This will configure your Nomad client to talk to the provisioned cluster.

To launch a local proxy to the Nomad cluster:

  go run ../proxy/main.go -ca-file=${path.module}/certs/ca.crt -cert-file=${path.module}/certs/nomad.crt -key-file=${path.module}/certs/nomad.key -endpoint=${module.nomad-c1m_us-east-1.nomad_addr}

EOM
}
