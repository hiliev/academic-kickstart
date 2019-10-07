+++
title = "Recovering Datasets from Broken ZFS raidz Pools"
date = 2017-07-09T20:15:00
draft = false
tags = ["zfs", "raidz", "data recovery"]
categories = []
aliases = ["/blog/recovering-datasets-from-broken-zfs-raidz-pools.html"]

# Featured image
# Place your image in the `static/img/` folder and reference its filename below, e.g. `image = "example.jpg"`.
[header]
image = ""
caption = ""
+++

There are generally two kinds of people--those who've suffered a severe data loss and those who are about to suffer a severe data loss.
I repeatedly jump back and forth between the two kinds.

Recently, a combination of hardware defects and a series of power outages rendered the raidz pool of the NAS of my previous research group unreadable.
The OS, an old Solaris 10 x86, would not import the pool with a dreaded I/O error message.
We tried importing in various modern OpenSolaris-based live distributions, even forcing the kernel to try and fix errors when possible, to no success.
Perhaps disabling the ZIL (because of performance problems with NFS clients) wasn't that good idea after all.
The lack of resources for proper preventive maintenance meant that there were no real backups to restore from.
Gone were a lot of research data, source codes, PhD theses, mails, and web content.
In the face of the growing despair, as it all happened in the middle of several ongoing project calls, and the rapidly approaching need to accept that the data is most likely gone for good and one has to start anew, I got curious--what could really break in the "unbreakable" ZFS?
Previous to that moment, ZFS was to me just a magical filesystem that can do all those things such as cheaply creating multiple filesets and instantaneous snapshots, and I never had real interest in learning how is this all implemented.
This time my curiosity won and I asked the sysadmin to wait a while before wiping the disks and let me first poke around the filesystem and see if I could make it readable again.
In the end, what started as a set of Python scripts to read and display on-disk data structures quickly grew into a very functional minimalistic ZFS implementation capable of reading and exporting entire datasets.

It turned out that a fundamental structure of the ZFS pool known as Meta Object Set (MOS) was badly damaged, therefore the pool couldn't be restored to an importable state, at least not without a more than considerable amount of effort, but reading what was readable brought back to life 1.4 TiB of data, among which all the research data and theses.
Most of the hard work in restoring the data happened automatically using a Python tool I assembled in the process.
It wasn't easy to develop, especially given the poor state of implementation information about ZFS and the differences between the on-disk format and the one described in the only official documentation I was able to find online, therefore I'm making it available under open-source license in hope that it could help someone else too.
Most kudos go to Max Bruning for his conference talks on YouTube and especially the [ZFS Raidz Data Walk](http://mbruning.blogspot.de/2009/12/zfs-raidz-data-walk.html) blog article and to the FreeBSD project for their excellent port of ZFS, which served as reference source code for some of the modules in my implementation.

The tool--aptly named `py-zfs-rescue`--is available under the 3-clause BSD license in its [GitHub repo](https://github.com/hiliev/py-zfs-rescue).

## Technical Details

`py-zfs-rescue` is not for the faint of heart as there are no command-line options of any kind and the configuration is performed exclusively by altering the source code, therefore some knowledge of Python 3 is required.
Also, one has to have a good idea of how ZFS is structured internally, thus I provide here a quick overview of the ZFS on-disk format.

ZFS is an incredibly complex filesystem, but fundamentally it is just a huge tree of *blocks* with the leaf blocks containing data and the rest containing various types of metadata.
The tree is rooted in what is known as *uberblock*, which serves the same purpose as the superblock in most filesystems.
The uberblock itself (actually an entire array of uberblocks) is part of the ZFS *label*, four copies of which are found on any device, disk partition or file that are part of a ZFS vdev and contains besides the uberblock array a collection of key-value pairs with information about the type of the vdev and its constituent elements.
A typical label (in a 6-dev raidz1) looks like this:

``` text
txg: 8510825
name: pool
version: 10
guid: 6106808927530115088
vdev_tree:
  children[0]:
    guid: 6106808927530115088
    id: 0
    type: disk
    path: /dev/dsk/c3t0d0s7
    devid: id1,sd@f0000000049be3b9a000ea8d90002/h
    whole_disk: 0
    phys_path: /pci@0,0/pci15d9,d280@1f,2/disk@0,0:h
    DTL: 35
  ... two children omitted for brevity ...
  children[3]:
    guid: 9245908906035854570
    id: 3
    type: disk
    path: /dev/dsk/c3t3d0s7
    faulted: 1
    devid: id1,sd@f0000000049bbf10a000ac4500003/h
    whole_disk: 0
    phys_path: /pci@0,0/pci15d9,d280@1f,2/disk@3,0:h
    DTL: 33
  ... two children omitted for brevity ...
  guid: 14559490109128549798
  asize: 2899875201024
  nparity: 1
  id: 0
  metaslab_array: 14
  metaslab_shift: 34
  is_log: 0
  ashift: 9
  type: raidz
hostid: 237373741
pool_guid: 1161904676014256579
hostname: spof
state: 0
top_guid: 14559490109128549798
```

The label contains the pool `name` (`pool` in our case), the `guid` of the component, the ZFS version, the list of vdevs in the pool, their type and constituent devices (`vdev_tree`), the pool `state`, and information about the host that the pool belongs to (ours is named `spof` for Single Point Of Failure, which it indeed proved to be...)
By matching the GUIDs of the individual vdev components with the GUIDs in the `vdev_tree` list the OS is capable of assembling the pool even if the device names/paths change.
Faulty components are marked accordingly like the fourth child (`/dev/dsk/c3t3d0s7`) in this case.
There are two copies of the label at the beginning of each component and two copies at the end.

Each and every I/O operation in ZFS is performed in the context of a specific transaction, which groups a set of modifications to the data stored on the disk.
When a ZFS object is written to the disk, the transaction number is recorded as part of the metadata.
Unlike most other filesystems, ZFS stores data and metadata in blocks of varying sizes.
Each block is located by its *block pointer*, which holds the type of the block, checksum of its contents, the location and physical (eventually compressed) size (collectively known as DVA) of up to three copies of the block data, the logical size of the data, and the compression type.

ZFS is organised as a set of objects with each object represented by a *dnode* (equivalent to the *inode* in Unix filesystems) containing pointers to up to three associated groups of data blocks.
For some really small objects the data is stored within the free space of the dnode block itself and there are no associated data blocks.
dnodes are organised in arrays called *Object Sets* with the notable exception of the dnode for the top-level object set (the MOS), a pointer to which is located in the uberblock.
By default, there are three copies of the MOS, two copies of the other metadata objects including the object sets and directory objects, and a single copy of the file data blocks.
The metadata blocks are usually compressed with [LZJB](https://en.wikipedia.org/wiki/LZJB) (LZ4 in newer ZFS versions) while the file data blocks are uncompressed unless the dataset is configured accordingly.
There is a maximum block size of 128 KiB and larger objects are stored using block trees with blocks at the nodes containing arrays of block pointers to the lower levels.
Some simple modulo and integer division arithmetic is used to figure out which intermediate (*indirect* in ZFS terminology) block at each level of the tree contains the relevant pointer.
The depth of the block tree is stored in the dnode.
All top-level objects such as datasets, dataset property lists, space maps, snapshots, etc., are stored in the MOS.

Datasets are implemented as separate object sets consisting of all files and directories in a given dataset plus two (or more in newer ZFS implementations) special ZFS objects--the *master node* of the dataset and the *delete queue*.
A typical dataset looks like this:

``` text
[ 0] <unallocated dnode>
[ 1] [ZFS master node] 1B 1L/16384 blkptr[0]=<[L0 ZFS master node] 200L/200P DVA[0]=<0:92e4c6400:600> DVA[1]=<0:b1ca2b1800:600> birth=448585 fletcher4 off LE contiguous fill=1>
[ 2] [ZFS delete queue] 1B 1L/16384 blkptr[0]=<[L0 ZFS delete queue] 200L/200P DVA[0]=<0:b2024e5c00:600> DVA[1]=<0:13110532c00:600> birth=449850 fletcher4 off LE contiguous fill=1>
[ 3] [ZFS directory] 1B 1L/16384 blkptr[0]=<[L0 ZFS directory] 200L/200P DVA[0]=<0:b2024e5800:600> DVA[1]=<0:13110532800:600> birth=449850 fletcher4 off LE contiguous fill=1> bonus[264]
[ 4] [ZFS plain file] 1B 1L/16384 blkptr[0]=<[L0 ZFS plain file] 200L/200P DVA[0]=<0:92e4ff400:600> birth=448593 fletcher2 off LE contiguous fill=1> bonus[264]
[ 5] [ZFS plain file] 1B 1L/16384 blkptr[0]=<[L0 ZFS plain file] 200L/200P DVA[0]=<0:92e4ffc00:600> birth=448593 fletcher2 off LE contiguous fill=1> bonus[264]
[ 6] [ZFS plain file] 1B 1L/16384 blkptr[0]=<[L0 ZFS plain file] 200L/200P DVA[0]=<0:92e500000:600> birth=448593 fletcher2 off LE contiguous fill=1> bonus[264]
[ 7] [ZFS plain file] 1B 1L/16384 blkptr[0]=<[L0 ZFS plain file] 200L/200P DVA[0]=<0:b0c5cd3400:600> birth=450114 fletcher2 off LE contiguous fill=1> bonus[264]
[ 8] [ZFS directory] 1B 1L/16384 blkptr[0]=<[L0 ZFS directory] 200L/200P DVA[0]=<0:95e52f000:600> DVA[1]=<0:b1ce66a400:600> birth=449176 fletcher4 off LE contiguous fill=1> bonus[264]
... (many) more dnodes ...
```

Directories are implemented simply as key-value pair collections with the file name being the key and a bit field of the index in the object set and the file type the value and are stored in so-called *ZAPs* (ZAP stands for ZFS Attribute Processor).
The master node of each dataset (always at index 1 in the object set) contains the index of the root directory's ZAP, which index tends to be always equal to `3`.
File metadata such as owner, permissions, ACLs, timestamps, etc. is stored in the file's dnode.
In order to reach the content of a specific file in a given dataset, the following has to be done:

* Locate the dataset's dnode in the MOS
* Read the content of the dataset's object set
* Read the master node to find the root directory's index
* Read the root directory to find the index of the next directory in the file path
* Repeat recursively the directory traversal until the index of the file object is found
* Walk the associated block tree to find pointers to all the file data blocks

The Python tool is capable of recursively following the root directory of a given dataset and either producing a CSV file with the content of the fileset (similar to `ls -lR`) or creating a `tar` file of the content with the associated metadata (owner, timestamps, and permissions).
It keeps symbolic links but ignores device nodes and special files.
It is possible to configure it to skip certain objects (provided as lists of IDs), which is useful when working with really large datasets.
The current version performs caching of certain objects, most notably the block trees, and achieves about 11 MiB/s read speed on our faulted server without any read-ahead optimisations.
A peculiar feature is the ability to access the pool remotely via a simple binary TCP protocol, e.g., over an SSH tunnel, which is exactly how I was using it throughout the entire development process.
This was more a result of the way the program was developed than a deliberate design decision, but I think it's pretty nifty.
ZFS mirror and raidz1 vdevs as implemented in ZFS version 10 (the one that an ancient Solaris 10 x86 comes with) are supported.
For raidz1 the tool is able to recover information on faulty devices using the checksum.
Up to date status information is available on the project's GitHub page.

I really hope nobody will ever need to use this tool.
