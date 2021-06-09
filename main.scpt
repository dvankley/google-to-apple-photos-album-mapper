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
let APPLY_ALBUM_MEMBERSHIP = 'false';

/**
 * If true, photos in Google albums that are not present in the Apple photo library will be
 * 	imported and added to the corresponding album.
 * If false, photos will not be imported, only reorganized in the Apple photo library if they're found.
 */
let COPY_MISSING_PHOTOS = 'false';

/**
 * Entry point
 */
function run(...argv) {
	// Not sure why all the passed in args are an array in argv[0] and argv[1] is an empty object,
	//	and the docs sure aren't going to tell me.

	// Use this line for CLI
	const [pathArg, membershipArg, copyArg] = argv[0];
	// And these lines for Script Editor
	// const pathArg = undefined;
	// const membershipArg = undefined;
	// const copyArg = undefined;

	const path = pathArg ?? '/Users/dvankley/Downloads/Takeout/Takeout1/Google Photos/Test Album';
	// const path = '/Users/dvankley/Downloads/Takeout';
	APPLY_ALBUM_MEMBERSHIP = (membershipArg ?? APPLY_ALBUM_MEMBERSHIP) === 'true';
	COPY_MISSING_PHOTOS = (copyArg ?? COPY_MISSING_PHOTOS) === 'true';
	console.log(`Running for path ${path} with APPLY_ALBUM_MEMBERSHIP ${APPLY_ALBUM_MEMBERSHIP} and ` +
		`COPY_MISSING_PHOTOS ${COPY_MISSING_PHOTOS}`);

	const directoryNames = appSys.folders.byName(path).folders.name();
	if (directoryNames.length > 0) {
		// If the path contains sub-directories, then try to process all albums
		console.log(`Subdirectories found, attempting to process multiple takeout exports and albums`);
		runForAllAlbums(path);
	} else {
		// Otherwise treat this as a single album
		console.log(`No subdirectories found, attempting to process this as a single album`);
		const [appleAlbumsByName, indexedApplePhotosAll, indexedApplePhotosByAlbum] = fetchGlobalApplePhotosMetadata();
		let matchedPhotoFilenames = {};
		matchForSingleAlbum(
			path,
			appleAlbumsByName,
			indexedApplePhotosAll,
			indexedApplePhotosByAlbum,
			matchedPhotoFilenames,
		);
		importForSingleAlbum(
			path,
			appleAlbumsByName,
			indexedApplePhotosAll,
			indexedApplePhotosByAlbum,
			matchedPhotoFilenames,
		);
	}
}

/**
 * @param {string} topLevelPath 
 */
function runForAllAlbums(topLevelPath) {
	const takeoutDirectoryNames = appSys.folders.byName(topLevelPath).folders.name();
	console.log(`Found Google Photos takeout directories ${takeoutDirectoryNames.join(', ')}; processing each ` +
		`and merging results together.`)

	const [appleAlbumsByName, indexedApplePhotosAll, indexedApplePhotosByAlbum] = fetchGlobalApplePhotosMetadata();
	let matchedPhotoFilenames = {};
	let takeoutDirectoriesByGoogleAlbumNames = {};

	// Google doesn’t do a good job breaking up albums.
	//	You can end up with a photo’s metadata file in one chunk and the actual image file in the other, so 
	//	We need to do a first pass and get a set of all unique album names across all takeout directories first
	//	so we can match and import bsaed on the aggregate of all metadata for a given album
	for (const takeoutDirectoryName of takeoutDirectoryNames) {
		const albumNames = appSys.folders.byName(`${topLevelPath}/${takeoutDirectoryName}`).folders.name();
		for (const albumName of albumNames) {
			if (!takeoutDirectoriesByGoogleAlbumNames.hasOwnProperty(albumName)) {
				takeoutDirectoriesByGoogleAlbumNames[albumName] = [];
			}
			takeoutDirectoriesByGoogleAlbumNames[albumName].push(takeoutDirectoryName);
		}
	}

	// Iterate over each album and aggregate data from all takeout directories that have data for that album
	for (const albumName of Object.keys(takeoutDirectoriesByGoogleAlbumNames)) {
		const takeoutDirectoryNames = takeoutDirectoriesByGoogleAlbumNames[albumName];
		console.log(`Processing ${takeoutDirectoryNames.length} takeout directories for album ${albumName}`);

		for (takeoutDirectoryName of takeoutDirectoryNames) {
			console.log(`Mapping takeout directory ${takeoutDirectoryName} for album ${albumName}`);
			const path = `${topLevelPath}/${takeoutDirectoryName}/${albumName}`;
			matchForSingleAlbum(
				path,
				appleAlbumsByName,
				indexedApplePhotosAll,
				indexedApplePhotosByAlbum,
				matchedPhotoFilenames,
			);
		}

		// Iterate over all files again for importing. This is a separate loop because some images don't
		//	have corresponding metadata files but we still want to import them.
		//	This means we have to do all matching first.
		for (takeoutDirectoryName of takeoutDirectoryNames) {
			console.log(`Importing album ${albumName} for takeout directory ${takeoutDirectoryName}`);
			const path = `${topLevelPath}/${takeoutDirectoryName}/${albumName}`;
			importForSingleAlbum(
				path,
				appleAlbumsByName,
				indexedApplePhotosAll,
				indexedApplePhotosByAlbum,
				matchedPhotoFilenames,
			);
		}
	}

	// for (const takeoutDirectoryName of takeoutDirectoryNames) {
	// 	const albumNames = appSys.folders.byName(`${topLevelPath}/${takeoutDirectoryName}`).folders.name();
	// 	console.log(`Importing ${albumNames.length} albums for takeout directory ${takeoutDirectoryName}`);
	// 	for (const albumName of albumNames) {
	// 		console.log(`Importing album ${albumName} for takeout directory ${takeoutDirectoryName}`);
	// 		const path = `${topLevelPath}/${takeoutDirectoryName}/${albumName}`;
	// 		importForSingleAlbum(
	// 			path,
	// 			appleAlbumsByName,
	// 			indexedApplePhotosAll,
	// 			indexedApplePhotosByAlbum,
	// 			matchedPhotoFilenames,
	// 		);
	// 	}
	// }
}

/**
 * @param {string} albumPath 
 * @param appleAlbumsByName Object.<string, Album>
 * @param indexedApplePhotosAll Object.<string, MediaItem> All Apple photos indexed by photo key from getPhotoIndexKey()
 * @param indexedApplePhotosByAlbum Object.<string, Object.<string, MediaItem>> Same as indexedApplePhotosAll, except
 * 	a top level of grouping by album name.
 * This function is expected to keep this up to date by adding new album and photo entries if it modifies the state
 * 	of Apple Photos.
 * @param matchedPhotoFilenames Object.<string, string> A set of filenames (keys and values) that exist in Google and
 * 	were matched by key from getPhotoIndexKey() to an Apple photo
 * This function is expected to populate this as it searches for photo matches.
 */
function matchForSingleAlbum(
	albumPath,
	appleAlbumsByName,
	indexedApplePhotosAll,
	indexedApplePhotosByAlbum,
	matchedPhotoFilenames,
) {
	const albumName = albumPath.substring(albumPath.lastIndexOf('/') + 1);
	console.log(`Mapping Google to Apple photos for album ${albumName} from directory ${albumPath}`);

	const albumFileNames = appSys.folders.byName(albumPath).diskItems.name();
	const metaMetadataFilenames = [
		'metadata.json',
		'user-generated-memory-titles.json',
		'shared_album_comments.json',
		'print-subscriptions.json',
	];
	// Iterate over all .json metadata files to attempt to match up Google photos with original Apple photos
	for (const albumFileName of albumFileNames) {
		if (metaMetadataFilenames.indexOf(albumFileName) !== -1 || !albumFileName.endsWith('.json')) {
			// We only care about the per-image metadata files in this loop; we'll grab relevant image files if we need
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
				if (indexedApplePhotosByAlbum[albumName].hasOwnProperty(key)) {
					console.log(`Photo ${filename} already belongs to Apple album ${albumName}; skipping adding it.`);
				} else {
					console.log(`Adding photo ${filename} to album ${albumName}`);
					const album = getOrCreateTopLevelAppleAlbum(appleAlbumsByName, albumName, indexedApplePhotosByAlbum);
					moveApplePhotoToAlbum(matchedItem, album, indexedApplePhotosByAlbum);
				}
			} else {
				console.log(`Would have added photo ${filename} to album ${albumName}`);
			}
		} else {
			console.log(`Failed to find matching Apple photo for Google photo ${key}.`);
		}
	}
}

/**
 * @param {string} albumPath 
 * @param appleAlbumsByName Object.<string, Album>
 * @param indexedApplePhotosAll Object.<string, MediaItem> All Apple photos indexed by photo key from getPhotoIndexKey()
 * @param indexedApplePhotosByAlbum Object.<string, Object.<string, MediaItem>> Same as indexedApplePhotosAll, except
 * 	a top level of grouping by album name
 * @param matchedPhotoFilenames Object.<string, string> A set of filenames (keys and values) that exist in Google and
 * 	were matched by key from getPhotoIndexKey() to an Apple photo in matchForSingleAlbum, and presumably added to
 * 	an album if requested.
 */
function importForSingleAlbum(
	albumPath,
	appleAlbumsByName,
	indexedApplePhotosAll,
	indexedApplePhotosByAlbum,
	matchedPhotoFilenames,
) {
	const pathParts = albumPath.split('/');
	const albumName = pathParts[pathParts.length - 1];
	const albumFileNames = appSys.folders.byName(albumPath).diskItems.name();
	for (const filename of albumFileNames) {
		if (filename.endsWith('.json') || filename.endsWith('.html')) {
			// We only care about image files in this loop.
			continue;
		}
		if (matchedPhotoFilenames.hasOwnProperty(filename)) {
			console.log(`Google photo ${filename} was already matched with an Apple photo; not importing.`);
			continue;
		}
		if (COPY_MISSING_PHOTOS) {
			console.log(`Importing Google photo ${filename} into Apple album ${albumName}.`);
			const album = getOrCreateTopLevelAppleAlbum(appleAlbumsByName, albumName, indexedApplePhotosByAlbum);
			const photo = importGooglePhoto(`${albumPath}/${filename}`, album);
			moveApplePhotoToAlbum(photo, album, indexedApplePhotosByAlbum);
		} else {
			console.log(`Would have imported Google photo ${filename} into Apple album ${albumName}.`);
		}
	}
}

/**
 * Pull various global metadata from Apple Photos
 * @returns {[
	appleAlbumsByName: Object.<string, Album>,
	indexedApplePhotosAll: Object.<string, MediaItem>,
	indexedApplePhotosByAlbum: Object.<string, Object.<string, MediaItem>>
]}
 */
function fetchGlobalApplePhotosMetadata() {
	const appleAlbumsByName = indexByCallback(p.albums(), album => album.name());

	// Save time whilst testing
	const indexedApplePhotosAll = indexApplePhotosForCollection(p.search({ for: 'IMG_7892.HEIC' }));
	// const indexedApplePhotosAll = indexApplePhotosForCollection(p.mediaItems());

	// Save time whilst testing
	const indexedApplePhotosByAlbum = indexApplePhotosForAllAlbums(p.albums().filter(album => album.name() === 'Test Album'));
	// const indexedApplePhotosByAlbum = indexApplePhotosForAllAlbums(p.albums());

	return [appleAlbumsByName, indexedApplePhotosAll, indexedApplePhotosByAlbum];
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
		const key = getApplePhotoIndexKey(item);
		if (out.hasOwnProperty(key)) {
			console.log(`Conflict: item ${item.filename()} has same key ${key} as ${out[key].filename()}`);
			continue;
		}
		console.log(`Indexing Apple Photos item ${key}`);
		out[key] = item;
	}
	return out;
}

/**
 * @param {MediaItem} photo 
 * @returns {string}
 */
function getApplePhotoIndexKey(photo) {
	const timestamp = photo.date().getTime() / 1000;
	const filename = photo.filename();
	return getPhotoIndexKey(filename, timestamp);
}

/**
 * Returns the unique key for a photo.
 * Currently this is a concatenation of the Google photoTakenTime and the filename. This may 
 * 	be changed if it doesn't serve as a unique enough identifier.
 * @param {string} filename 
 * @param {number} timestamp 
 */
function getPhotoIndexKey(filename, timestamp) {
	return `${filename}|${timestamp}`;
}

/**
 * Returns an existing top level Apple Photos album if it already exists, otherwise creates one.
 * @param {Object.<string, Album>} albumsByName 
 * @param {string} name 
 * @param indexedApplePhotosByAlbum Object.<string, Object.<string, MediaItem>> Same as indexedApplePhotosAll, except
 * 	a top level of grouping by album name.
 * This function is expected to keep this up to date by adding new album and photo entries if it modifies the state
 * 	of Apple Photos.
 * @returns 
 */
function getOrCreateTopLevelAppleAlbum(albumsByName, name, indexedApplePhotosByAlbum) {
	let album = albumsByName[name];

	if (!album) {
		album = createTopLevelAppleAlbum(name);
		console.log(`Created apple album "${album.name()}" with id ${album.id()}`)
		albumsByName[name] = album;
		indexedApplePhotosByAlbum[name] = {};
	}
	return album;
}

/**
 * Creates an Apple Photos album at the top level, that is, not nested in any other folders or albums.
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
 * Adds a media item that already exists in Apple Photos into a given album.
 * @param {MediaItem} photo 
 * @param {Album} album 
 * @param indexedApplePhotosByAlbum Object.<string, Object.<string, MediaItem>> Same as indexedApplePhotosAll, except
 * 	a top level of grouping by album name.
 * This function is expected to keep this up to date by adding new album and photo entries if it modifies the state
 * 	of Apple Photos.
 */
function moveApplePhotoToAlbum(photo, album, indexedApplePhotosByAlbum) {
	p.add([photo], { to: album });
	indexedApplePhotosByAlbum[album.name()][getApplePhotoIndexKey(photo)] = photo;
}

/**
 * Imports a photo from path into Apple photos.
 * Does not add the photo into an album because that param doesn't work for unknown reasons. Use
 * 	moveApplePhotoToAlbum for that.
 * @param {string} path 
 * @returns MediaItem
 */
function importGooglePhoto(path) {
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
