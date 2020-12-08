module "control_plane_asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 3.0"

  name = "c1m-control-${var.project}"

  image_id        = var.ami_id
  instance_type   = var.instance_type
  security_groups = var.security_groups

  root_block_device = [
    {
      volume_size = "50"
      volume_type = "gp2"
    },
  ]

  ephemeral_block_device = var.ephemeral_storage ? [
    {
      device_name  = "/dev/xvdb"
      virtual_name = "ephemeral0"
    }
  ] : []
  load_balancers = var.elb_ids

  iam_instance_profile = var.iam_instance_profile_name

  # Auto scaling group
  vpc_zone_identifier       = var.subnet_ids
  health_check_type         = "ELB"
  min_size                  = var.cluster_size
  max_size                  = var.cluster_size
  desired_capacity          = var.cluster_size
  wait_for_capacity_timeout = 0
  key_name                  = var.ssh_key_name

  user_data_base64 = base64encode(<<EOT
#!/bin/bash
PUBLIC_IPV4=$(curl -sf "http://169.254.169.254/latest/meta-data/public-ipv4")

DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=${var.dd_key} DD_SITE="datadoghq.com" bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"

sudo tee /etc/nomad.d/nomad.hcl > /dev/null <<EOC

advertise {
  serf = "$PUBLIC_IPV4"
}

${templatefile("${path.module}/templates/nomad.hcl",
    {
      region       = var.nomad_region
      datacenter   = var.nomad_datacenter
      cluster_size = var.cluster_size
      tag_key      = var.cluster_tag_key
      tag_value    = var.cluster_tag_value
})}


EOC


%{if var.enable_tls}
sudo mkdir /etc/nomad.d/tls
sudo tee /etc/nomad.d/tls/ca_cert.pem > /dev/null <<EOC
${var.tls_ca_cert_pem}
EOC
%{if var.nomad_server}
sudo tee /etc/nomad.d/tls/cert.pem > /dev/null <<EOC
${var.tls_server_cert_pem}
EOC
sudo tee /etc/nomad.d/tls/key.pem > /dev/null <<EOC
${var.tls_server_key_pem}
EOC
%{else}
sudo tee /etc/nomad.d/tls/cert.pem > /dev/null <<EOC
${var.tls_client_cert_pem}
EOC
sudo tee /etc/nomad.d/tls/key.pem > /dev/null <<EOC
${var.tls_client_key_pem}
EOC
%{endif}
%{endif}

%{if var.ephemeral_storage}
DEVICE=$(lsblk -do PATH,PTTYPE | grep -v gpt | tail -1 | awk '{print $1}')
sudo mkfs.ext4 $${DEVICE}
sudo mkdir /opt/nomad/data
sudo mount $${DEVICE} /opt/nomad/data
%{endif}

sudo service nomad enable
sudo service nomad start

tee -a /home/admin/.bashrc > /dev/null <<EOC
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_CACERT=/etc/nomad.d/tls/ca_cert.pem
export NOMAD_CLIENT_CERT=/etc/nomad.d/tls/cert.pem
export NOMAD_CLIENT_KEY=/etc/nomad.d/tls/key.pem
export NOMAD_SKIP_VERIFY=1
EOC

sudo tee /home/admin/.ssh/authorized_keys > /dev/null <<EOK
${var.authorized_keys}
EOK
EOT
)

tags = flatten(
  [
    {
      key                 = var.cluster_tag_key
      value               = var.cluster_tag_value
      propagate_at_launch = true
    },
    var.tags,
  ]
)
}

