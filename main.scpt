const p = Application('Photos');

/**
 * Uncomment if you're running from the command line
 * This function is called when the script is invoked from the command line
 */
// function run(...args) {
// 	main(args[0]);
// }

// Uncomment this if you're running the script in Script Editor because it doesn't 
//	automatically call the run function
processSingleAlbum('/Users/dvankley/Downloads/Takeout1/Google Photos');

function main() {

}

/**
 * @param {string} albumPath 
 * @param {boolean} dryRun 
 */
function processSingleAlbum(albumPath, dryRun) {
	console.log(`Mapping Google to Apple photos from takeout directory ${JSON.stringify(albumPath)}`);
	
	const applePhotosByTimestamp = indexApplePhotosByTimestamp();


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

}

function findMatchingApplePhoto() {

}

function importGooglePhoto() {

}

function moveApplePhotoToAlbum() {

}
