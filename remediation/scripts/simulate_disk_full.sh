#!/bin/bash
echo "Creating 5GB file to trigger disk alert..."
dd if=/dev/zero of=/tmp/panoptes_disk_test bs=1M count=5000
echo "Cleanup: rm /tmp/panoptes_disk_test"
