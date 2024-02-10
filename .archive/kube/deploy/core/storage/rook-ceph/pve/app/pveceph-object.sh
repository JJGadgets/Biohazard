#!/bin/bash
pveceph pool create ".rgw.root" --add_storages 0 --application rgw --size 3 --min_size 2 --pg_autoscale_mode on --pg_num 4
pveceph pool create "${CLUSTER_NAME}.rgw.control" --add_storages 0 --application rgw --size 3 --min_size 2 --pg_autoscale_mode on --pg_num 32
pveceph pool create "${CLUSTER_NAME}.rgw.meta" --add_storages 0 --application rgw --size 3 --min_size 2 --pg_autoscale_mode on --pg_num 32
pveceph pool create "${CLUSTER_NAME}.rgw.log" --add_storages 0 --application rgw --size 3 --min_size 2 --pg_autoscale_mode on --pg_num 4
pveceph pool create "${CLUSTER_NAME}.rgw.otp" --add_storages 0 --application rgw --size 3 --min_size 2 --pg_autoscale_mode on --pg_num 4
pveceph pool create "${CLUSTER_NAME}.rgw.buckets.index" --add_storages 0 --application rgw --size 3 --min_size 2 --pg_autoscale_mode on --pg_num 32
pveceph pool create "${CLUSTER_NAME}.rgw.buckets.non-ec" --add_storages 0 --application rgw --size 3 --min_size 2 --pg_autoscale_mode on --pg_num 32
pveceph pool create "${CLUSTER_NAME}.rgw.buckets.data" --add_storages 0 --application rgw --size 3 --min_size 2 --pg_autoscale_mode on --pg_num 64
