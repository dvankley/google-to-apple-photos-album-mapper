# NOTE: this project is still a work in progress, so don't expect anything of it yet

# Google to Apple Photos Mapper
A tool to help with migrating photos from Google Photos to Apple Photos.

I made this tool to make the migration process easier for myself and decided others might find it useful.

## Why You Might Want To Use This
I've used Google Photos for a while with the 'high quality' (read: limited quality) setting, but Google recently announced Photos "unlimited free 'high quality' storage" would be going away.
That combined with other reasons that are not relevant to this project led me to move to Apple Photos and iCloud.
However, I still have a lot of the original versions of my photos on my and my family members' devices and didn't want to permanently incur whatever 'high quality' downscaling Google applied to my uploaded photos.
We've also spent a lot of time organizing photos into Google Photos albums that we don't want to lose when migrating.

If this sounds like your situation, this project may help you.

## Why You Might Not Want To Use This
- If your photos aren't/weren't high resolution enough to be downscaled in Google Photos' 'high quality' mode and you're happy straight importing them into Apple Photos, then that might be good enough for your needs, although apparently it [can still be a pain](https://discussions.apple.com/thread/250486578).
- If you're not comfortable with running Mac automation scripts

## Caveats
- This process will result in duplicates across user Apple Photos libraries for photos that are in the "shared" Google photo library (multiple users can see them in their photo library due to library sharing) but not in an album. This is because Apple currently has no concept of shared libraries, so we have no way of sharing between users (and thus matching and deduping) photos that are not in albums.
- Some Google photos are exported without metadata JSON files. This appears to be primarily in cases where the photos weren't uploaded to Google Photos via a Google Photos app (i.e. raw file upload from a DSLR or whatever). In those cases we don't have enough metadata to do effective matching, so they will never be matched and will always be imported (if importing is enabled). This can result in duplicates.
- Apple Live Photos will map to already existing Live Photos in the Apple Photos library, but if no existing files are found, they will import as separate image and movie files.
- Multiple Google Photos in the same album with the same filename will be renamed by the filesystem to avoid collisions, with parenthetical numbers at the end (i.e. "IMG_12345 (1).jpg"). This will break metadata matching. This should be indicated by "Failed to find expected image file" errors in the script output for all runs, including
dry runs. You should fix this (by excluding the album in question or renaming the files and file references in the metadata files) before running an import or you may get duplicates.

## Arguments
1. Target Google Takeout directory. Should be the top-level `Takeout` directory, which will have subdirectories as follows:
    1. Takeout1
        1. Google Photos
            1. Album1
            1. Album2
            1. Album3
            1. etc.
    1. Takeout2
        1. Google Photos
            1. Album2
            1. etc.
1. Target working directory. This will be where the script puts its various output files.
1. `APPLY_ALBUM_MEMBERSHIP`
    1. Should be `true` or `false`.
    1. If true, Google Photos that are matched to Apple Photos will be added to corresponding Apple Photos albums.
    1. If false, no album membership will be changed, but all logic will still be run and JSON output files will be generated.
1. `COPY_MISSING_PHOTOS`
    1. Should be `true` or `false`.
    1. If true, Google Photos that have no matching Apple Photos will be imported into Apple Photos.
    1. If false, no new photos will be imported, but all logic will still be run and JSON output files will be generated.

## Process
### Setup
1. Create [a copy of the Apple Photos library](https://support.apple.com/guide/photos/back-up-the-photos-library-pht6d60d10f/6.0/mac/11.0) for each user involved, and store it in a safe place.
    1. This is so if this process goes totally FUBAR, you can wipe out the resulting Apple Photos libraries and iCloud photos and restore from backup.
1. Choose the user you want to own the shared albums. This should probably be the user with most of the originals.
1. Have a Mac user account available for each user who needs to migrate over, as well as any iOS devices that contain the original photos you want to preserve and organize.
1. Ensure iCloud photo sync is turned off on the Mac in question.
1. Import all photos from the iOS devices to the Mac.
1. Go to takeout.google.com and export the user’s Google photos library.
### Dry Run
1. Create [a copy of your Apple Photos library](https://support.apple.com/guide/photos/back-up-the-photos-library-pht6d60d10f/6.0/mac/11.0)
and do a dry run of both "Photo Album Mapping" and "Missing Photo Import" below (including both `APPLY_ALBUM_MEMBERSHIP` and `COPY_MISSING_PHOTOS` set
to `true`, excluding enabling iCloud sync) against that library first to avoid potential bugs or misconfigurations affecting your primary library.
### Photo Album Mapping
1. Run the script with `APPLY_ALBUM_MEMBERSHIP` and `COPY_MISSING_PHOTOS` both false.
    1. Remove all logged duplicates in the Apple Photos library.
    1. Sanity check the JSON output files in the working directory to ensure the script is behaving as expected.
    1. `COPY_MISSING_PHOTOS` is false in this case to avoid duplicates from other users sharing this library that might have the original versions of photos in this particular album.
1. Enable iCloud photo sync for this user and let the sync process complete.
    1. Note this part is irreversible (aside from wiping out your iCloud photo library and restoring from the backup(s) you should have made at the start), so make sure you've done a dry run and sanity check first and are comfortable with the results. No guarantees are provided as to what this software will do, and you don't want to have to go through thousands of photos and remove duplicates.
        1. From the [Apple docs](https://support.apple.com/guide/photos/create-additional-libraries-pht6d60b524/6.0/mac/11.0):
        > Important: If you switch to another library, Photos automatically turns off iCloud Photos and Shared Albums. You can turn them on again in the iCloud pane of Photos preferences. When you turn on iCloud Photos after designating a new System Photo Library, the photos stored in iCloud are merged with those in the new System Photo Library. After the content from the new System Photo Library is uploaded to iCloud, the libraries cannot be unmerged, so consider carefully before changing your System Photo Library.
1. Share all albums that other users may have originals of (or just that you want to share in general).
1. Repeat "Setup" steps 2-5 and "Photo Album Mapping" steps 1-3 for all users.
    1. This should result in other users' originals imported into their Apple Photos libraries and assigned to the appropriate shared albums.
### Missing Photo Import
1. At this point, all users should have all of their original photos imported to their Mac and organized into albums based on the organization info in Google Photos.
No photos that didn’t have corresponding originals with one of your users should have been copied from Google Photos to Apple Photos at this time. If this is all you wanted, you're done.
1. Now set `COPY_MISSING_PHOTOS` to true and re-run the script for each user. This will result in any photos that only exist on the Google side being copied from Google to Apple.
    1. This may result in duplicates across users for photos not in albums, and for photos without metadata files, as noted in “Caveats”.
    1. Keep an eye on the Apple Photos window while this is running. Apple Photos does its own duplicate detection and may prompt you in the UI to resolve a conflict, which will cause the script to time out if you take too long to respond.
1. Donezo.