FROM docker.elastic.co/elasticsearch/elasticsearch:7.6.2

RUN bin/elasticsearch-plugin install --batch discovery-ec2