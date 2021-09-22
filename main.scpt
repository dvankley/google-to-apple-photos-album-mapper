// IMPORTS
const p = Application('Photos');
const finder = Application('Finder');
const app = Application.currentApplication()
app.includeStandardAdditions = true
const appSys = Application('System Events');
ObjC.import('Cocoa');

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
 * Set to true to update files that are imported with the timestamp specified in their corresponding Google Photos
 * 	metadata file.
 * The intended result is that the photo timestamp in Apple Photos matches the timestamp in the Google Photos metadata.
 */
const UPDATE_IMPORTED_FILE_TIMESTAMPS = true;

/**
 * For some reason, sometimes the image filename in a Google Photos metadata file will be longer than the actual filename.
 * Usually this happens if the filename is over 46 characters.
 * I have no idea why this is. Maybe a limitation in filename length when zipping or exporting image files?
 * Enabling this flag will cause the script to see if it can find any image files in the same album that have a prefix
 * 	matching the filename in the metadata file. If only a single file has a prefix matching the target filename, that
 * 	will be used instead.
 * If this flag is disabled and an image file can't be found for a given metadata file, an error will be logged and the
 * 	file will be skipped.
 */
const TRY_FUZZY_MATCHING_MISSING_FILENAMES = true;
// const MAX_LENGTH_DIFF_FUZZY_MATCH = 20;

/**
 * A set of filenames that should be excluded from the import process.
 * 
 * Current reasons for filenames to be on this list:
 * - The movie component of an Apple Live Photo that was found to already exist in Apple Photos.
 */
let importExcludedFilenameSet = {};

const extensionRegex = /\.([\w\d]{3,4})$/i;
const parenthesisRegex = /\(\d+\)\./i;
const parenthesisAndExtensionRegex = /(\(\d+\))?\s*\.([\w\d]{3,4})$/i;

// ENTRY POINT
function run(...argv) {
	// Not sure why all the passed in args are an array in argv[0] and argv[1] is an empty object,
	//	and the docs sure aren't going to tell me.

	// Use this line for CLI
	const [takeoutPathArg, scriptPathArg, membershipArg, copyArg] = argv[0];
	// And these lines for Script Editor
	// const takeoutPathArg = undefined;
	// This arg is only required because JXA sucks and provides no workable method for getting the running script directory:
	//	https://stackoverflow.com/questions/68047177/javascript-for-automation-how-to-get-the-path-of-the-current-script
	// const scriptPathArg = undefined;
	// const membershipArg = undefined;
	// const copyArg = undefined;

	const takeoutPath = takeoutPathArg ?? '/Users/dvankley/Downloads/Takeout/Takeout1/Google Photos/Test Album';
	const scriptPath = scriptPathArg ?? '/Users/dvankley/dev/google-to-apple-photos-album-mapper';
	APPLY_ALBUM_MEMBERSHIP = (membershipArg ?? APPLY_ALBUM_MEMBERSHIP) === 'true';
	COPY_MISSING_PHOTOS = (copyArg ?? COPY_MISSING_PHOTOS) === 'true';
	console.log(`Running for takeout path ${takeoutPath} with working directory ${scriptPath}, APPLY_ALBUM_MEMBERSHIP ${APPLY_ALBUM_MEMBERSHIP} and ` +
		`COPY_MISSING_PHOTOS ${COPY_MISSING_PHOTOS}`);

	const directoryNames = appSys.folders.byName(takeoutPath).folders.name();
	if (directoryNames.length > 0) {
		// If the path contains sub-directories, then try to process all albums
		console.log(`Subdirectories found, attempting to process multiple takeout exports and albums`);
		runForAllAlbums(takeoutPath, scriptPath);
	} else {
		// Otherwise treat this as a single album
		console.log(`No subdirectories found, attempting to process this as a single album`);
		const [
			appleAlbumsByName,
			indexedApplePhotosByKey,
			indexedApplePhotosByFilename,
			indexedApplePhotosByAlbumAndKey
		] = fetchGlobalApplePhotosMetadata(takeoutPath);
		let matchedPhotoFilenames = {};
		matchForSingleAlbum(
			takeoutPath,
			scriptPath,
			appleAlbumsByName,
			indexedApplePhotosByKey,
			indexedApplePhotosByFilename,
			indexedApplePhotosByAlbumAndKey,
			matchedPhotoFilenames,
		);
		importForSingleAlbum(
			takeoutPath,
			scriptPath,
			appleAlbumsByName,
			indexedApplePhotosByKey,
			indexedApplePhotosByFilename,
			indexedApplePhotosByAlbumAndKey,
			matchedPhotoFilenames,
		);
	}
}

/**
 * @param {string} topLevelPath 
 * @param {string} workingPath
 */
function runForAllAlbums(topLevelPath, workingPath) {
	const takeoutDirectoryNames = appSys.folders.byName(topLevelPath).folders.name();
	console.log(`Found Google Photos takeout directories ${takeoutDirectoryNames.join(', ')}; processing each ` +
		`and merging results together.`)

	const [
		appleAlbumsByName,
		indexedApplePhotosByKey,
		indexedApplePhotosByFilename,
		indexedApplePhotosByAlbumAndKey
	] = fetchGlobalApplePhotosMetadata(topLevelPath);
	let matchedPhotoFilenames = {};
	let takeoutDirectoriesByGoogleAlbumNames = {};

	// Google doesn’t do a good job breaking up albums.
	// You can end up with a photo’s metadata file in one chunk and the actual image file in the other, so 
	//	We need to do a first pass and get a set of all unique album names across all takeout directories first
	//	so we can match and import based on the aggregate of all metadata for a given album.
	for (const takeoutDirectoryName of takeoutDirectoryNames) {
		const albumNames = appSys.folders.byName(`${topLevelPath}${takeoutDirectoryName}/Google Photos`).folders.name();
		for (const albumName of albumNames) {
			if (!takeoutDirectoriesByGoogleAlbumNames.hasOwnProperty(albumName)) {
				takeoutDirectoriesByGoogleAlbumNames[albumName] = [];
			}
			takeoutDirectoriesByGoogleAlbumNames[albumName].push(takeoutDirectoryName);
		}
	}

	// The metadata files only give the filename of the image, not the takeout chunk that it's in, so we also
	//	need to index all image files by the takeout chunk they're in so we can find them.
	// We're just going to index all files rather than try to figure out all possible image file extensions.
	let imageFilePathsByAlbum = {};

	for (const albumName of Object.keys(takeoutDirectoriesByGoogleAlbumNames)) {
		imageFilePathsByAlbum[albumName] = {};
		const takeoutDirectoryNames = takeoutDirectoriesByGoogleAlbumNames[albumName];

		for (const takeoutDirectoryName of takeoutDirectoryNames) {
			const albumPath = `${topLevelPath}/${takeoutDirectoryName}/Google Photos/${albumName}`;
			const albumFileNames = appSys.folders.byName(albumPath).diskItems.name();
			for (const albumFileName of albumFileNames) {
				imageFilePathsByAlbum[albumName][albumFileName] = `${albumPath}/${albumFileName}`;
			}
		}
	}

	// Iterate again over each album and aggregate data from all takeout directories that have data for that album
	for (const albumName of Object.keys(takeoutDirectoriesByGoogleAlbumNames)) {
		const takeoutDirectoryNames = takeoutDirectoriesByGoogleAlbumNames[albumName];
		console.log(`Processing ${takeoutDirectoryNames.length} takeout directories for album ${albumName}`);

		for (takeoutDirectoryName of takeoutDirectoryNames) {
			console.log(`Mapping takeout directory ${takeoutDirectoryName} for album ${albumName}`);
			const path = `${topLevelPath}/${takeoutDirectoryName}/Google Photos/${albumName}`;
			matchForSingleAlbum(
				path,
				workingPath,
				appleAlbumsByName,
				indexedApplePhotosByKey,
				indexedApplePhotosByFilename,
				indexedApplePhotosByAlbumAndKey,
				matchedPhotoFilenames,
				imageFilePathsByAlbum[albumName],
			);
		}

		// Iterate over all files again for importing. This is a separate loop because some images don't
		//	have corresponding metadata files but we still want to import them.
		//	This means we have to do all matching first.
		for (takeoutDirectoryName of takeoutDirectoryNames) {
			console.log(`Importing album ${albumName} for takeout directory ${takeoutDirectoryName}`);
			const path = `${topLevelPath}/${takeoutDirectoryName}/Google Photos/${albumName}`;
			importForSingleAlbum(
				path,
				workingPath,
				appleAlbumsByName,
				indexedApplePhotosByKey,
				indexedApplePhotosByFilename,
				indexedApplePhotosByAlbumAndKey,
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
 * @param {string} workingPath
 * @param appleAlbumsByName Object.<string, Album>
 * @param indexedApplePhotosAll Object.<string, MediaItem> All Apple photos indexed by photo key from getPhotoIndexKey()
 * 	The values are a single photo because the photo key should be unique.
 * @param indexedApplePhotosByFilename Object.<string, MediaItem[]> All Apple photos indexed by filename.
 * 	The values are an array because there can be multiple files with the same filename.
 * @param indexedApplePhotosByAlbum Object.<string, Object.<string, MediaItem>> Same as indexedApplePhotosAll, except
 * 	a top level of grouping by album name.
 * This function is expected to keep this up to date by adding new album and photo entries if it modifies the state
 * 	of Apple Photos.
 * @param matchedPhotoFilenames Object.<string, string> A set of filenames (keys and values) that exist in Google and
 * 	were matched by key from getPhotoIndexKey() to an Apple photo
 * This function is expected to populate this as it searches for photo matches.
 * @param imageFilePaths Object.<string, Object.<string, true>> Keys are the filenames of all image files
 * 	(or all files in general) that belong to this album. Value is the path of the given filename.
 * This is only useful if working across multiple Takeout chunks.
 */
function matchForSingleAlbum(
	albumPath,
	workingPath,
	appleAlbumsByName,
	indexedApplePhotosAll,
	indexedApplePhotosByFilename,
	indexedApplePhotosByAlbum,
	matchedPhotoFilenames,
	imageFilePaths = {},
) {
	const albumName = albumPath.substring(albumPath.lastIndexOf('/') + 1);
	console.log(`Mapping Google to Apple photos for album ${albumName} from directory ${albumPath}`);

	const albumFileNames = appSys.folders.byName(albumPath).diskItems.name();
	// Create a set of file names so we can check for their existence in O(1)
	let albumFileNameSet = {};
	for (const albumFileName of albumFileNames) {
		albumFileNameSet[albumFileName] = true;
	}

	const metaMetadataFilenames = [
		'user-generated-memory-titles.json',
		'shared_album_comments.json',
		'print-subscriptions.json',
	];
	let matchedPhotos = {};
	let unmatchedPhotos = {};
	// Iterate over all .json metadata files to attempt to match up Google photos with original Apple photos

	// There are some Google photos without metadata files. These appear to primarily be photos from sources aside
	//	from smartphones (i.e. DSLRs or whatever), which implies that the Google Photos app syncing process may
	//	be responsible for generating metadata.
	// Anyhoo, these photos will never match up because we don't have timestamp metadata for them.
	for (const albumFileName of albumFileNames) {
		if (metaMetadataFilenames.indexOf(albumFileName) !== -1 ||
			// This isn't in metaMetadataFilenames because it can have metadata(1).json variants
			albumFileName.startsWith('metadata') ||
			!albumFileName.endsWith('.json')
		) {
			// We only care about the per-image metadata files in this loop; we'll grab relevant image files if we need
			//	to later.
			continue;
		}

		// console.log(`Reading metadata for ${albumFileName}`);
		const rawImageMetadata = app.read(Path(`${albumPath}/${albumFileName}`));
		const imageMetadata = JSON.parse(rawImageMetadata);
		// console.log(`Image ${albumFileName} metadata: ${rawImageMetadata}`);

		const timestamp = imageMetadata.photoTakenTime.timestamp;
		const rawFilename = imageMetadata.title;
		let filename = sanitizeFilename(rawFilename);
		let filepath = imageFilePaths[filename];
		if (!filepath) {
			// Couldn't find the image file we're looking for

			if (TRY_FUZZY_MATCHING_MISSING_FILENAMES) {
				const metadataFilenameExtensionResults = filename.match(extensionRegex);
				if (!metadataFilenameExtensionResults) {
					const extensionMatch = tryPossibleImageExtensions(filename, imageFilePaths);
					if (extensionMatch) {
						console.log(`Successfully to found extension ${extensionMatch} for filename ${filename} referenced in metadata file ${albumPath}/${albumFileName}`);
						filename = extensionMatch;
						filepath = imageFilePaths[filename];
					} else {
						console.log(`Failed to find extension for filename ${filename} referenced in metadata file ${albumPath}/${albumFileName}`);
						continue;
					}
				}
				const metadataFilenameExtension = metadataFilenameExtensionResults[1];
				// Try some fuzzy matching shenanigans to find the file we're looking for
				const prefixMatchingFilenames = Object
					.keys(imageFilePaths)
					// TODO: optimize this so we're not repeatedly stripping the extension for the same filename
					.filter((existingFilename) => {
						const existingFilenameSansExtension = existingFilename.replace(parenthesisAndExtensionRegex, '');
						const metadataFilenameSansExtension = filename.replace(parenthesisAndExtensionRegex, '');
						if (filename.startsWith(existingFilenameSansExtension)
							&& existingFilename.endsWith(metadataFilenameExtension)) {
								
							return true;
						} else {
							return false;
						}
					});
				if (prefixMatchingFilenames.length === 1) {
					// console.log(`Fuzzy match succeeded for filename ${filename} referenced in metadata file ${albumPath}/${albumFileName}`);
					filename = prefixMatchingFilenames[0];
					filepath = imageFilePaths[filename];
				} else {
					console.log(`Fuzzy matching failed missing cross-chunk file for filename ${filename} referenced in metadata file ${albumPath}/${albumFileName}` +
					` failed; found ${prefixMatchingFilenames.length} prefix matching filenames: ${JSON.stringify(prefixMatchingFilenames)}`);
					continue;
				}
			} else {
				console.log(`Failed to find cross-chunk file path for filename ${filename} referenced in metadata file ${albumPath}/${albumFileName}`);
				continue;
			}
		}
		
		if (!doesFileExist(filepath)) {
			console.log(`Failed to find expected image file ${filepath} referenced in metadata file ${albumPath}/${albumFileName}`);
			continue;
		}

		const key = getPhotoIndexKey(filename, timestamp);

		updatePhotoFileTimestamp(timestamp, filepath);

		ignoreLivePhotos(filepath, albumFileNameSet);

		const matchedItem = indexedApplePhotosAll[key];
		// if (Object.values(matchedItems).length !== 1) {
		// 	console.log(`Photo ${filename} with timestamp ${timestamp} has ${matchedItems.length} duplicates; skipping matching.` +
		// 		`You should investigate and manually remove these duplicates.`);
		// 	continue;
		// }
		// const matchedItem = matchedItems[0];

		if (matchedItem) {
			// console.log(`Found matching Apple photo for Google photo ${key}`);
			matchedPhotoFilenames[filename] = filename;
			matchedPhotos[key] = key;
			if (APPLY_ALBUM_MEMBERSHIP) {
				if (indexedApplePhotosByAlbum[albumName] &&
					indexedApplePhotosByAlbum[albumName].hasOwnProperty(key)
				) {
					console.log(`Photo ${filename} already belongs to Apple album ${albumName}; skipping adding it.`);
				} else {
					console.log(`Adding photo ${filename} to album ${albumName}`);
					const album = getOrCreateTopLevelAppleAlbum(appleAlbumsByName, albumName, indexedApplePhotosByAlbum);
					moveApplePhotoToAlbum(matchedItem, album, indexedApplePhotosByAlbum);
				}
			} else {
				// console.log(`Would have added photo ${filename} to album ${albumName}`);
			}
		} else {
			// console.log(`Failed to find matching Apple photo for Google photo ${key}.`);
			unmatchedPhotos[key] = key;
		}
	}
	if (!isObjectEmpty(matchedPhotos)) {
		writeTextToFile(JSON.stringify(matchedPhotos), `${workingPath}/${albumName}_matchedPhotos.json`);
	}
	if (!isObjectEmpty(unmatchedPhotos)) {
		writeTextToFile(JSON.stringify(unmatchedPhotos), `${workingPath}/${albumName}_unmatchedPhotos.json`);
	}
}

/**
 * @param {string} filename A filename without extension to try image filename extensions for.
 * @param {Object.<string, string>} imageFilePaths An object keyed by filenames that exist in the Google Photos folders for this album.
 * @return {string|null} The first matching filename if found. Null if no matches were found.
 */
function tryPossibleImageExtensions(filename, imageFilePaths)
{
	const possibleImageExtensions = [
		'jpg',
		'jpeg',
		'heic',
		'png',
	];

	for (const extension of possibleImageExtensions) {
		const lower = `${filename}.${extension}`;
		if (imageFilePaths.hasOwnProperty(lower)) {
			return lower;
		}
		const upper = `${filename}.${extension.toUpperCase()}`;
		if (imageFilePaths.hasOwnProperty(upper)) {
			return upper;
		}
	}
	return null;
}

/**
 * @param {string} filename 
 * @returns {string} The filename sanitized to match observed behavior of downloading and extracting Google Photos files
 * 	in Mac or Windows.
 */
function sanitizeFilename(filename)
{
	const sanitizeRegex = /[&'%\/]/g;
	let newFilename = filename.replaceAll(sanitizeRegex, '_');

	return newFilename;
}

/**
 * @param {string} path 
 * @returns True if a file exists at {@link path}, false if not.
 */
function doesFileExist(path)
{
	let error = false;
	try {
		app.doShellScript(`test -f "${path}"`);
	} catch (e) {
		error = true;
	}
	return !error;
}

/**
 * Checks if this file's creation timestamp does not match the photo timestamp in the Google Photos metadata
 * 	and the config flag is set to update that. If so, update's the file's creation timestamp in the filesystem.
 * 
 * @param {number} metadataTimestamp
 * @param {string} filepath
 */
function updatePhotoFileTimestamp(
	metadataTimestamp,
	filepath,
) {
	if (UPDATE_IMPORTED_FILE_TIMESTAMPS) {
		// Get the creation date of the file
		const rawTimestamp = app.doShellScript(`stat -f "%B" "${filepath}"`);
		const fileTimestamp = parseInt(rawTimestamp, 10);

		if (fileTimestamp !== metadataTimestamp) {
			// console.log(`Timestamp mismatch for path ${filepath}; updating file creation timestamp from ` +
				// `${fileTimestamp} to ${metadataTimestamp}`);
			app.doShellScript(`touch -t "$(date -r ${metadataTimestamp} +%Y%m%d%H%M.%S)" "${filepath}"`)
		}
	}
}

/**
 * @param {string} filename 
 * @returns {string} filename with the extension removed.
 */
function removeExtension(filename)
{
	return filename.replace(extensionRegex, '');
}

/**
 * Checks if this JSON file corresponds to an image file that also has an mp4 movie (an Apple Live Photo),
 * 	if so, then marks the movie to be ignored when importing by updating {@link importExcludedFilenameSet}.
 * 
 * @param {string} filename
 * @param {Object.<string, boolean>} albumFileNameSet
 */
function ignoreLivePhotos(
	filename,
	albumFileNameSet,
) {
	const filenameWithoutExtension = removeExtension(filename);
	// console.log(`Raw filename ${filename}; without extension: ${filenameWithoutExtension}`);

	const livePhotoFilenames = [
		`${filenameWithoutExtension}.mp4`,
		`${filenameWithoutExtension}.MP4`,
	]
	for (const livePhotoFilename of livePhotoFilenames) {
		if (albumFileNameSet.hasOwnProperty(livePhotoFilename)) {
			console.log(`Live photo ${filename} detected; ignoring ${livePhotoFilename} for import.`);
			importExcludedFilenameSet[livePhotoFilename] = true;
			break;
		}
	}
}

/**
 * @param {string} albumPath
 * @param {string} workingPath
 * @param appleAlbumsByName Object.<string, Album>
 * @param indexedApplePhotosAll Object.<string, MediaItem> All Apple photos indexed by photo key from getPhotoIndexKey()
 * 	The values are a single photo because the photo key should be unique.
 * @param indexedApplePhotosByFilename Object.<string, MediaItem[]> All Apple photos indexed by filename.
 * 	The values are an array because there can be multiple files with the same filename.
 * @param indexedApplePhotosByAlbum Object.<string, Object.<string, MediaItem>> Same as indexedApplePhotosAll, except
 * 	a top level of grouping by album name
 * @param matchedPhotoFilenames Object.<string, string> A set of filenames (keys and values) that exist in Google and
 * 	were matched by key from getPhotoIndexKey() to an Apple photo in matchForSingleAlbum, and presumably added to
 * 	an album if requested.
 * Also includes photos that were imported. This is to ensure that a given photo is only imported once, even if it's
 * 	in multiple Google Photo albums.
 */
function importForSingleAlbum(
	albumPath,
	workingPath,
	appleAlbumsByName,
	indexedApplePhotosAll,
	indexedApplePhotosByFilename,
	indexedApplePhotosByAlbum,
	matchedPhotoFilenames,
) {
	const pathParts = albumPath.split('/');
	const albumName = pathParts[pathParts.length - 1];
	const albumFileNames = appSys.folders.byName(albumPath).diskItems.name();
	let importedPhotos = {};
	let importFailedPhotos = {};
	for (const filename of albumFileNames) {
		if (
			// We only care about image files in this loop.
			filename.endsWith('.json') ||
			filename.endsWith('.html') ||
			// Also ignore the "-edited" versions of image files because the originals are still present
			//	and those are all we want to import
			filename.includes('-edited.')
		) {
			continue;
		}
		if (matchedPhotoFilenames.hasOwnProperty(filename)) {
			// console.log(`Google photo ${filename} was already matched with an Apple photo; not importing.`);
			continue;
		}
		if (importExcludedFilenameSet.hasOwnProperty(filename)) {
			console.log(`Google photo ${filename} explicitly marked as import excluded; not importing.`);
			continue;
		}
		importedPhotos[filename] = filename;
		if (COPY_MISSING_PHOTOS) {
			console.log(`Importing Google photo ${filename} into Apple album ${albumName}.`);
			const album = getOrCreateTopLevelAppleAlbum(appleAlbumsByName, albumName, indexedApplePhotosByAlbum);
			let photo = importGooglePhotoIntoApplePhotos(`${albumPath}/${filename}`);
			matchedPhotoFilenames[filename] = filename;
			if (!photo) {
				// Import failed for some reason, probably Apple Photos duplicate detection
				// Let's see if we can find the duplicate
				const dupes = indexedApplePhotosByFilename[filename];
				if (dupes) {
					if (dupes.length === 1) {
						console.log(`Importing Google photo ${filename} failed because it's a duplicate. Applying album membership to the duplicate.`);
						photo = dupes[0];
					} else {
						console.log(`Importing Google photo ${filename} failed because it has multiple duplicates. You should manually fix this conflict.`);
						importFailedPhotos[filename] = filename;
						continue;
					}
				} else {
					console.log(`Importing Google photo ${filename} failed for unknown reasons.`);
					importFailedPhotos[filename] = filename;
					continue;
				}
			}
			moveApplePhotoToAlbum(
				photo,
				album,
				indexedApplePhotosByAlbum
			);
		} else {
			// console.log(`Would have imported Google photo ${filename} into Apple album ${albumName}.`);
		}
	}
	if (!isObjectEmpty(importedPhotos)) {
		writeTextToFile(JSON.stringify(importedPhotos), `${workingPath}/${albumName}_importedPhotos.json`);
	}
	if (!isObjectEmpty(importFailedPhotos)) {
		writeTextToFile(JSON.stringify(importFailedPhotos), `${workingPath}/${albumName}_importFailedPhotos.json`);
	}
}

const APPLE_PHOTOS_ALL_CACHE_FILENAME = 'apple_photos_all_cache.json';
const APPLE_PHOTOS_BY_ALBUM_CACHE_FILENAME = 'apple_photos_by_album_cache.json';

/**
 * Pull various global metadata from Apple Photos
 * @param {string} cachePath
 * @returns {[
	appleAlbumsByName: Object.<string, Album>,
	indexedApplePhotosByKey: Object.<string, MediaItem>,
	indexedApplePhotosByFilename: Object.<string, MediaItem[]>,
	indexedApplePhotosByAlbum: Object.<string, Object.<string, MediaItem>>
]}
 */
function fetchGlobalApplePhotosMetadata(cachePath) {
	console.log(`Fetching Apple Photos metadata. This will take a while.`);
	const appleAlbumsByName = indexByCallback(p.albums(), album => album.name());

	// const allCachePath = `${cachePath}/${APPLE_PHOTOS_ALL_CACHE_FILENAME}`;
	// const indexedApplePhotosAllCache = readCacheFile(allCachePath);
	// Save time whilst testing
	// const indexedApplePhotosAll = indexedApplePhotosAllCache ?? indexApplePhotosForCollection(p.search({ for: 'IMG_7892.HEIC' }));
	// const indexedApplePhotosAll = indexApplePhotosForCollection(p.search({ for: 'IMG_7892.HEIC' }));
	const allItems = p.mediaItems();
	const indexedApplePhotosByKey = indexApplePhotosByKey(allItems);
	const indexedApplePhotosByFilename = indexApplePhotosByFilename(allItems);
	// const indexedApplePhotosAll = indexedApplePhotosAllCache ?? indexApplePhotosForCollection(p.mediaItems());
	// if (!indexedApplePhotosAllCache) {
	// 	console.log(`Caching ${allCachePath}`);
	// 	writeTextToFile(JSON.stringify(indexedApplePhotosAll), allCachePath, true);
	// }

	// const byAlbumCachePath = `${cachePath}/${APPLE_PHOTOS_BY_ALBUM_CACHE_FILENAME}`;
	// const indexedApplePhotoByAlbumCache = readCacheFile(byAlbumCachePath);
	// Save time whilst testing
	// const indexedApplePhotosByAlbum = indexedApplePhotoByAlbumCache ?? indexApplePhotosForAllAlbums(p.albums().filter(album => album.name() === 'Test Album'));
	// const indexedApplePhotosByAlbum = indexApplePhotosForAllAlbums(p.albums().filter(album => album.name() === 'Test Album'));
	const indexedApplePhotosByAlbumAndKey = indexApplePhotosByKeyForAllAlbums(p.albums());
	// const indexedApplePhotosByAlbum = indexedApplePhotoByAlbumCache ?? indexApplePhotosForAllAlbums(p.albums());
	// if (!indexedApplePhotoByAlbumCache) {
	// 	console.log(`Caching ${byAlbumCachePath}`);
	// 	writeTextToFile(JSON.stringify(indexedApplePhotosByAlbum), byAlbumCachePath, true);
	// }

	return [appleAlbumsByName, indexedApplePhotosByKey, indexedApplePhotosByFilename, indexedApplePhotosByAlbumAndKey];
}

// function readCacheFile(path) {
// 	try {
// 		const rawCache = app.read(Path(path));
// 		return JSON.parse(rawCache);
// 	} catch (error) {
// 		console.log(`Failed to read cache file ${path}, reading from application`);
// 		return null;
// 	}
// }

/**
 * Indexes photos by album and subindexes by getPhotoIndexKey()
 * @param {Album[]}
 * @returns {Object.<string, Object.<string, MediaItem>>}
 */
function indexApplePhotosByKeyForAllAlbums(collection) {
	let out = {};
	console.log(`Indexing apple photos for all albums`);
	for (const album of collection) {
		// console.log(`Indexing Apple Photos for album ${album.name()}`);
		out[album.name()] = indexApplePhotosByKey(album.mediaItems(), getApplePhotoIndexKey);
	}
	return out;
}

/**
 * Indexes all photos in collection by getPhotoIndexKey()
 * @param {MediaItem[]} collection
 * @returns {Object.<string, MediaItem>}
 */
function indexApplePhotosByKey(collection) {
	let out = {};
	for (const item of collection) {
		const key = getApplePhotoIndexKey(item);
		if (out.hasOwnProperty(key)) {
			console.log(`Conflict: item ${item.filename()} has same key ${key} as ${out[key].filename()}. ` +
				`You should manually fix this.`);
			continue;
		}
		// console.log(`Indexing Apple Photos item ${key}`);
		out[key] = item;
	}
	return out;
}

/**
 * Indexes all photos in collection by filename. Since multiple photos with the same filename are possible,
 * 	the returns an array per filename.
 * @param {MediaItem[]} collection
 * @returns {Object.<string, MediaItem[]>}
 */
function indexApplePhotosByFilename(collection) {
	let out = {};
	for (const item of collection) {
		const key = item.filename();
		if (!out.hasOwnProperty(key)) {
			out[key] = [];
		}
		out[key].push(item);
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
 * @param {MediaItem} photo 
 * @returns {string}
 */
function getFilename(photo) {
	return photo.filename();
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
 * @returns {?MediaItem}
 */
function importGooglePhotoIntoApplePhotos(path) {
	// to: "add to album" param doesn't work for some reason, so add the photo to an album separately
	const result = p.import([Path(path)]);
	if (!result) {
		// This can be null if the import failed, which is usually because this is a duplicate that Apple Photos
		//	skipped at the behest of the user.
		return null;
	}
	return result[0];
}

function indexByCallback(array, callback) {
	let out = {};
	for (item of array) {
		out[callback(item)] = item;
	}
	return out;
}

/**
 * Writes text to a file.
 * The Apple documentation example for writing text to a file (below) doesn't work correctly,
 * 	but this seems to.
 * @param text 
 * @param file 
 * @param overwrite 
 * @returns {boolean}
 */
function writeTextToFile(text, file, overwrite) {
	// source: https://stackoverflow.com/a/44293869/11616368
	var nsStr = $.NSString.alloc.initWithUTF8String(text)
	var nsPath = $(file).stringByStandardizingPath
	var successBool = nsStr.writeToFileAtomicallyEncodingError(nsPath, false, $.NSUTF8StringEncoding, null)
	if (!successBool) {
		throw new Error("function writeFile ERROR:\nWrite to File FAILED for:\n" + file)
	}
	return successBool
};

/**
 * @param {object} obj 
 * @returns {boolean}
 */
function isObjectEmpty(obj) {
	return obj // null and undefined check
		&& Object.keys(obj).length === 0 && obj.constructor === Object;
}

// /**
//  * Writes text to a file
//  * @param {string} text 
//  * @param {string} path 
//  * @param {boolean} overwriteExistingContent 
//  * @returns {boolean}
//  */
// function writeTextToFile(text, path, overwriteExistingContent) {
// 	try {
// 		// Open the file for writing
// 		var openedFile = app.openForAccess(Path(path), { writePermission: true });

// 		// Clear the file if content should be overwritten
// 		if (overwriteExistingContent) {
// 			app.setEof(openedFile, { to: 0 });
// 		}

// 		// Write the new content to the file
// 		app.write(text, { to: openedFile, startingAt: app.getEof(openedFile) });

// 		// Return a boolean indicating that writing was successful
// 		return true;
// 	}
// 	catch (error) {
// 		console.log(`Error writing text to file: ${error}`);
// 		return false;
// 	}
// 	finally {
// 		try {
// 			// Close the file
// 			app.closeAccess(path);
// 		}
// 		catch (error) {
// 			// Report the error is closing failed
// 			console.log(`Couldn't close file: ${error}`);
// 		}
// 	}
// }
