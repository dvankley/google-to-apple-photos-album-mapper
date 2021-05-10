const p = Application('Photos');
const app = Application.currentApplication()
app.includeStandardAdditions = true
var appSys = Application('System Events');

/**
 * Uncomment if you're running from the command line
 * This function is called when the script is invoked from the command line
 */
// function run(...args) {
// 	main(args[0]);
// }

// Uncomment this if you're running the script in Script Editor because it doesn't 
//	automatically call the run function
processSingleAlbum('/Users/dvankley/Downloads/Takeout1/Google Photos/Test Album', true);

/**
 * @param {string} albumPath 
 * @param {boolean} dryRun 
 */
function processSingleAlbum(albumPath, dryRun) {
	console.log(`Mapping Google to Apple photos from takeout directory ${JSON.stringify(albumPath)}`);
	
	// const applePhotosByTimestamp = indexApplePhotosByTimestamp();
	// Save time whilst testing
	const applePhotosByTimestamp = {};

	const albumFileNames = appSys.folders.byName(albumPath).diskItems.name();
	for (const albumFileName of albumFileNames) {
		if (!albumFileName.endsWith('.json')) {
			// We only care about the metadata files in this loop; we'll grab relevant image files if we need
			//	to later.
			continue;
		}
		console.log(`Reading metadata for ${albumFileName}`);
		const rawImageMetadata = app.read(Path(albumFileName));
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
function indexApplePhotosByTimestamp() {
	console.log(`Indexing apple photos`);

	let out = {};
	for (const item of p.mediaItems()) {
		out[item.date().getTime()] = item;
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
