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
 * False basically functions as a dry run, where info will be logged but album membership won't be changed.
 */
const APPLY_ALBUM_MEMBERSHIP = false;


/**
 * Uncomment if you're running from the command line
 * This function is called when the script is invoked from the command line
 */
// function run(...args) {
// 	main(args[0]);
// }

// Uncomment this if you're running the script in Script Editor because it doesn't 
//	allow parameters.
processSingleAlbum('/Users/dvankley/Downloads/Takeout1/Google Photos/Test Album', true);

/**
 * @param {string} albumPath 
 * @param {boolean} dryRun 
 */
function processSingleAlbum(albumPath, dryRun) {
	console.log(`Mapping Google to Apple photos from takeout directory ${JSON.stringify(albumPath)}`);
	
	const applePhotosByTimestamp = indexApplePhotos();
	// Save time whilst testing
	// const applePhotosByTimestamp = {};

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
		console.log(`Image ${albumFileName} metadata: ${rawImageMetadata}`);
	}


	for (const album of Application("Photos").albums()) {
		console.log(album.name());
	}
}

/**
 * @param {string} topLevelPath 
 * @param {boolean} dryRun 
 */
function processAllAlbums(topLevelPath, dryRun) {

}

/**
 * 
 */
function indexApplePhotos() {
	console.log(`Indexing apple photos`);

	let out = {};
	for (const item of p.mediaItems()) {
		const timestamp = item.date().getTime();
		const filename = item.filename();
		const key = `${filename}|${timestamp}`;
		if (out.hasOwnProperty(key)) {
			console.log(`Conflict: item ${item.filename()} has same key ${key} as ${out[key].filename()}`);
			continue;
		}
		out[key] = item;
	}
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
