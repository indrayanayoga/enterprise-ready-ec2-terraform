#!/bin/bash

#Set timestamp to GMT+7 
timedatectl set-timezone Asia/Bangkok

#Install rsyslog to forward logs to /var/log/messages
sudo yum install -y rsyslog
sudo systemctl enable --now rsyslog

#Install cloudwatch agent, configure metrics and logs
yum install -y amazon-cloudwatch-agent

cat << 'EOF' > /opt/aws/amazon-cloudwatch-agent/bin/config.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60,
        "resources": ["*"],
        "totalcpu": true
      },
      "mem": {
        "measurement": ["mem_used_percent", "mem_available", "mem_total", "mem_used"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "nginx-vm-logs",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%b %d %H:%M:%S",
            "timezone": "Local"
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "nginx-access-log",
            "log_stream_name": "{instance_id}-access",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "timezone": "Local"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "nginx-error-log",
            "log_stream_name": "{instance_id}-error",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "timezone": "Local"
          }
        ]
      }
    },
    "log_stream_name": "default-stream",
    "force_flush_interval": 15
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json \
  -s

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status

systemctl enable amazon-cloudwatch-agent

#Install Nginx
yum install -y nginx

echo "<html><body><h1>Hello World! This message is coming from the ${word} environment! </h1></body></html>" > /usr/share/nginx/html/index.html

systemctl start nginx
systemctl enable nginx
