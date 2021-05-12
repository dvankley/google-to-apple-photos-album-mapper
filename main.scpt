// IMPORTS
const p = Application('Photos');
const app = Application.currentApplication()
app.includeStandardAdditions = true
var appSys = Application('System Events');

// ARGUMENTS/GLOBAL PARAMETERS
// Defaults are set here, but run arguments may override them

/**
 * If true, Apple photos will be added to the album that the corresponding (same file name and timestamp)
 * 	Google photo is in.
 * False will still read and compare data, but album membership won't be changed.
 */
let APPLY_ALBUM_MEMBERSHIP = false;

/**
 * If true, photos in Google albums that are not present in the Apple photo library will be
 * 	imported and added to the corresponding album.
 * If false, photos will not be imported, only reorganized in the Apple photo library if they're found.
 */
let COPY_MISSING_PHOTOS = false;

/**
 * Entry point
 */
function run(...args) {
	// const path = args[0] ?? '/Users/dvankley/Downloads/Takeout/Takeout1/Google Photos/Test Album';
	const path = '/Users/dvankley/Downloads/Takeout';
	APPLY_ALBUM_MEMBERSHIP = Boolean(args[1] ?? APPLY_ALBUM_MEMBERSHIP);
	COPY_MISSING_PHOTOS = Boolean(args[2] ?? COPY_MISSING_PHOTOS);
	console.log(`Running for path ${path} with APPLY_ALBUM_MEMBERSHIP ${APPLY_ALBUM_MEMBERSHIP} and ` +
		`COPY_MISSING_PHOTOS ${COPY_MISSING_PHOTOS}`);

	const directoryNames = appSys.folders.byName(path).folders.name();
	if (directoryNames.length > 0) {
		// If the path contains sub-directories, then try to process all albums
		console.log(`Subdirectories found, attempting to process multiple albums`);
		runForAllAlbums(path);
	} else {
		// Otherwise treat this as a single album
		console.log(`No subdirectories found, attempting to process this as a single album`);
		runForSingleAlbum(path);
	}
}

/**
 * @param {string} topLevelPath 
 */
function runForAllAlbums(topLevelPath) {

	// const takeoutDirectoryNames = appSys.folders.byName();
}

/**
 * @param {string} albumPath 
 */
function runForSingleAlbum(albumPath) {
	const albumName = albumPath.substring(albumPath.lastIndexOf('/') + 1);
	console.log(`Mapping Google to Apple photos for album ${albumName} from directory ${albumPath}`);

	let albumsByName = indexByCallback(p.albums(), album => album.name());

	// Save time whilst testing
	const indexedApplePhotosAll = indexApplePhotosForCollection(p.search({ for: 'IMG_1681.JPG' }));
	// const indexedApplePhotosAll = indexApplePhotos(p.mediaItems());

	// const indexedApplePhotosByAlbum = {};
	const indexedApplePhotosByAlbum = indexApplePhotosForAllAlbums(p.albums());

	let matchedPhotoFilenames = {};
	const albumFileNames = appSys.folders.byName(albumPath).diskItems.name();
	// Iterate over all .json metadata files to attempt to match up Google photos with original Apple photos
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
			matchedPhotoFilenames[filename] = filename;
			if (APPLY_ALBUM_MEMBERSHIP) {
				console.log(`Adding photo ${filename} to album ${albumName}`);
				const album = getOrCreateTopLevelAppleAlbum(albumsByName, albumName);
				moveApplePhotoToAlbum(matchedItem, album);
			} else {
				console.log(`Would have added photo ${filename} to album ${albumName}`);
			}
		} else {
			console.log(`Failed to find matching Apple photo for Google photo ${key}.`);
		}
	}

	// Iterate over all files again for importing. This is a separate loop because some images don't
	//	have corresponding metadata files, but we still want to import them.
	for (const filename of albumFileNames) {
		if (filename.endsWith('.json') || filename.endsWith('.html')) {
			// We only care about image files in this loop.
			continue;
		}
		if (COPY_MISSING_PHOTOS) {
			console.log(`Importing Google photo ${filename} into Apple album ${albumName}.`);
			const album = getOrCreateTopLevelAppleAlbum(albumsByName, albumName);
			const photo = importGooglePhoto(`${albumPath}/${filename}`, album);
			moveApplePhotoToAlbum(photo, album);
		} else {
			console.log(`Would have imported Google photo ${filename} into Apple album ${albumName}.`);
		}
	}
}

/**
 * Indexes photos by album and subindexes by getPhotoIndexKey()
 * @param {Album[]}
 * @returns {Object.<string, Object.<string, MediaItem>>}
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
 * Indexes all photos in collection by getPhotoIndexKey()
 * @param {MediaItem[]}
 * @returns {Object.<string, MediaItem>}
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
 * @param {Object.<string, Album>} albumsByName 
 * @param {string} name 
 * @returns 
 */
function getOrCreateTopLevelAppleAlbum(albumsByName, name) {
	let album = albumsByName[name];

	if (!album) {
		album = createTopLevelAppleAlbum(name);
		console.log(`Created apple album "${album.name()} with id ${album.id()}"`)
		albumsByName[name] = album;
	}
	return album;
}

/**
 * @param {string} name 
 * @returns {Album} 
 */
function createTopLevelAppleAlbum(name) {
	console.log(`Album ${name} does not exist, creating`);
	album = p.make({
		new: 'album',
		named: name,
	});
	return album;
}

/**
 * @param {MediaItem} photo 
 * @param {Album} album 
 */
function moveApplePhotoToAlbum(photo, album) {
	p.add([photo], { to: album });
}

/**
 * @param {string} path 
 * @param {Album} album 
 * @returns MediaItem
 */
function importGooglePhoto(path, album) {
	// to: "add to album" param doesn't work for some reason, so add the photo to an album separately
	return p.import([Path(path)])[0];
}

function indexByCallback(array, callback) {
	let out = {};
	for (item of array) {
		out[callback(item)] = item;
	}
	return out;
}
