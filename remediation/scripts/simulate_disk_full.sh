#!/bin/bash
echo "Creating 5GB file to trigger disk alert..."
dd if=/dev/zero of=/tmp/umas_disk_test bs=1M count=5000
echo "Cleanup: rm /tmp/umas_disk_test"
