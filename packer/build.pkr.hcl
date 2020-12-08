build {
    sources = [ "source.amazon-ebs.nomad-c1m" ]

    provisioner "file" {
        source = "./linux"
        destination = "/tmp/linux"
    }

    provisioner "shell" {
        script = "./linux/setup.sh"
    }
}
