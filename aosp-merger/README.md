# aosp-merger

### Usage
Simply run the script from source top as follows:  
`./scripts/aosp-merger/aosp-merger.sh (--delete-staging) (--push-staging) <oldaosptag> <newaosptag>`  

* both `<oldaosptag>` and `<newaosptag>` are always required
* when using flags the script will perform the action(s) and exit
* set `DEFAULTBRANCH` to the default remote branch name
* set `DEFAULTREMOTE` to the default remote name
* set `WAIT_ON_CONFLICT` to `true` or `false` according to preference
* set `MANIFEST` var to the path of the manifest xml to search
* add repos *paths* that should not be upstreamed to `merge_blacklist.txt` -
sperated by newline

### Description
The script will go over the manifest file and try to merge the chosen AOSP tag for
any repo that is being tracked from `DEFAULTREMOTE` and is not in `merge_blacklist.txt`  
A log of actions will be saved to the source top dir at `merged_repos.txt` (see [this](#log-entries))  
Previously checked out branches will be saved to the source top dir at `saved_branches.list`
Any non pushed repos will be checked out to a staging branch

### Flags
##### --delete-staging
Will remove the staging branch for the given AOSP tag and exit
##### --push-staging
Will push (to the set default remote and branch / saved branches in `saved_branches.list`) and remove the remaining staging branches, while promting one by one

### Log entries
##### Positive
* `nochange <path>`: There was no change from previous tag
* `clean <path>`: Merged with no conflicts
* `solved <path>`: Merged after solving conflicts
* `pushed <path>`: Merge was pushed
* `fail <path>`: Merge failed

##### Negative
* `conflict <path>`: Conflicts in merge were not solved (kept for later)
* `invalid <path>`: AOSP remote is not valid or the repo doesn't even exist there
