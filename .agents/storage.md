# Storage Stack

## Rook-Ceph (primary HA storage)

`kube/deploy/core/storage/rook-ceph/cluster/biohazard/` — hyperconverged Ceph on Talos. 3 OSDs on Intel SSDs (encrypted), 3 MONs on control-plane nodes, 2 MGRs. CephFS has 3 data pools; RBD has block pools; RGW provides S3-compatible storage.

StorageClasses (defined in `storageclass.yaml` + HR values):
- `block` (RBD, default, 3-replica SSD, reclaim Delete) — for RWO PVCs like databases, app data needing backups.
- `block-2` (RBD, 2-replica SSD, reclaim Delete) — for RWO PVCs of non-critical data.
- `block-ssd-ec-2-1` (RBD, erasure-coded 2+1 SSD) — lower-overhead block storage.
- `file` (CephFS, 3-replica SSD data pool, reclaim Delete) — for RWX PVCs, shared data.
- `file-ec-2-1` (CephFS erasure-coded pool, reclaim Delete) — for mass non-critical RWX storage (thumbnails, caches, game server files).
- `file-size-2` (CephFS 2-replica, reclaim **Retain**) — for important mass storage (e.g. Immich library) where accidental deletion must be prevented.
- `rgw-biohazard` (RGW S3-backed) — for object storage PVCs.

## democratic-csi (local + NAS)

`kube/deploy/core/storage/democratic-csi/` — two drivers:
- `local` (local-hostpath, WaitForFirstConsumer, reclaim Delete) — for node-local single-replica PVCs like Postgres data (Crunchy default SC). No expansion support.
- `local-xfs` (local XFS hostpath, reclaim Delete, expansion supported) — fork of democratic-csi with XFS support (custom image `ghcr.io/jjgadgets/democratic-csi:xfs`).

## VolSync (backups)

`kube/deploy/core/storage/volsync/template/` — template consumed by per-app `<app>-pvc` Kustomizations (label `pvc.home.arpa/volsync: "true"`). Creates a PVC (from ReplicationDestination bootstrap), two ReplicationSources: scheduled (cron `0 */12 * * *`) and on-image-update (manual trigger keyed to `VS_APP_CURRENT_VERSION`), both via Restic to Cloudflare R2. Mover pods use `egress.home.arpa/r2: allow` label. Cache uses `block` SC.

## StorageClass selection guide

- **Databases (Crunchy Postgres)**: `local` (RWO, node-local, fast) — data is backed up via pgBackRest to R2 + RGW, not VolSync.
- **App data needing backups (RWX)**: `file` (CephFS 3-replica) + VolSync — e.g. Home Assistant config, OpenClaw data.
- **App data needing backups (RWO)**: `block` (RBD 3-replica) + VolSync — e.g. OpenClaw data PVC.
- **Important mass storage (RWX, retain)**: `file-size-2` (CephFS 2-replica, Retain) — e.g. Immich library.
- **Non-critical mass storage (RWX)**: `file-ec-2-1` (CephFS erasure-coded) — e.g. thumbnails, transcode, game server files. Cheap, no backup.
- **Non-critical RWO**: `block-2` (RBD 2-replica) — e.g. OpenClaw misc (Homebrew, Nix, Go cache).
- **NAS-attached**: mount NFS directly as a pod volume (not a PVC).
