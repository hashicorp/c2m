log_level = "INFO"
data_dir = "/opt/consul/data"
bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"
advertise_addr = "{{ GetPrivateIP }}"

datacenter = "util"

ui = true
server = true
bootstrap_expect = 3

retry_join = ["provider=aws tag_key=role tag_value=util"]
service {
  name = "consul"
}