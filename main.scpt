// IMPORTS
const p = Application('Photos');
const app = Application.currentApplication()
app.includeStandardAdditions = true
var appSys = Application('System Events');

// ARGUMENTS/GLOBAL PARAMETERS

/**
 * If true, photos in Google albums that are not present in the Apple photo library will be
 * 	imported and added to the corresponding album.
 * If false, photos will not be imported, only reorganized in the Apple photo library if they're found.
 */
const COPY_MISSING_PHOTOS = false;

/**
 * If true, Apple photos will be added to the album that the corresponding (same file name and timestamp)
 * 	Google photo is in.
 * False will still read and compare data, but album membership won't be changed.
 */
const APPLY_ALBUM_MEMBERSHIP = true;

/**
 * Entry point
 */
function run(...args) {
	runForSingleAlbum('/Users/dvankley/Downloads/Takeout/Takeout1/Google Photos/Test Album');
}

/**
 * @param {string} albumPath 
 * @param {boolean} dryRun 
 */
function runForSingleAlbum(albumPath, dryRun) {
	const albumName = albumPath.substring(albumPath.lastIndexOf('/') + 1);
	console.log(`Mapping Google to Apple photos for album ${albumName} from directory ${albumPath}`);

	const albumsByName = indexByCallback(p.albums(), album => album.name());

	// Save time whilst testing
	const indexedApplePhotosAll = indexApplePhotosForCollection(p.search({ for: 'IMG_1681.JPG' }));
	// const indexedApplePhotosAll = indexApplePhotos(p.mediaItems());

	// const indexedApplePhotosByAlbum = {};
	const indexedApplePhotosByAlbum = indexApplePhotosForAllAlbums(p.albums());

	const albumFileNames = appSys.folders.byName(albumPath).diskItems.name();
	for (const albumFileName of albumFileNames) {
		if (albumFileName === 'metadata.json' || !albumFileName.endsWith('.json')) {
			// We only care about the metadata files in this loop; we'll grab relevant image files if we need
			//	to later.
			continue;
		}
		console.log(`Reading metadata for ${albumFileName}`);
		const rawImageMetadata = app.read(Path(`${albumPath}/${albumFileName}`));
		const imageMetadata = JSON.parse(rawImageMetadata);
		// console.log(`Image ${albumFileName} metadata: ${rawImageMetadata}`);

		const timestamp = imageMetadata.photoTakenTime.timestamp;
		const filename = imageMetadata.title;
		const key = getPhotoIndexKey(filename, timestamp);

		const matchedItem = indexedApplePhotosAll[key];

		if (matchedItem) {
			console.log(`Found matching Apple photo for Google photo ${key}`);

			if (APPLY_ALBUM_MEMBERSHIP) {
				console.log(`Adding photo ${filename} to album ${albumName}`);

				let album = albumsByName[albumName];

				if (!album) {
					console.log(`Album ${albumName} does not exist, creating`);
					album = p.make({
						new: 'album',
						named: albumName,
					});
				}

				p.add([matchedItem], { to: album });
			}

			if (COPY_MISSING_PHOTOS) {
				//TODO
			}
		} else {
			console.log(`Failed to find matching Apple photo for Google photo ${key}`);
		}
	}
}

/**
 * @param {string} topLevelPath 
 * @param {boolean} dryRun 
 */
function runForAllAlbums(topLevelPath, dryRun) {

	// const takeoutDirectoryNames = appSys.folders.byName();
}

/**
 * Indexes photos by album and below that by getPhotoIndexKey()
 * @param {Album[]}
 * @return {Object.<string, Object.<string, MediaItem>>}
 */
function indexApplePhotosForAllAlbums(collection) {
	let out = {};
	for (const album of collection) {
		console.log(`Indexing Apple Photos for album ${album.name()}`);
		out[album.name()] = indexApplePhotosForCollection(album.mediaItems());
	}
	return out;
}

/**
 * Indexes all photos in the current Apple Photos library by getPhotoIndexKey()
 * @param {MediaItem[]}
 * @return {Object.<string, MediaItem>}
 */
function indexApplePhotosForCollection(collection) {
	let out = {};
	for (const item of collection) {
		const timestamp = item.date().getTime() / 1000;
		const filename = item.filename();
		const key = getPhotoIndexKey(filename, timestamp);
		if (out.hasOwnProperty(key)) {
			console.log(`Conflict: item ${item.filename()} has same key ${key} as ${out[key].filename()}`);
			continue;
		}
		console.log(`Indexing Apple Photos item ${key}: ${JSON.stringify(item)}`);
		out[key] = item;
	}
	return out;
}

/**
 * @param {string} filename 
 * @param {number} timestamp 
 */
function getPhotoIndexKey(filename, timestamp) {
	return `${filename}|${timestamp}`;
}

/**
 * @param {Object.<number, MediaItem} applePhotosByTimestamp 
 * @param {number} targetTimestamp 
 */
function findMatchingApplePhoto(applePhotosByTimestamp, targetTimestamp) {

}

function importGooglePhoto() {

}

function moveApplePhotoToAlbum() {

}

function indexByCallback(array, callback) {
	let out = {};
	for (item of array) {
		out[callback(item)] = item;
	}
	return out;
}
