const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

/**
 * Compresses an image file in place: downscales to fit within maxDimension
 * (longest side) and re-encodes as JPEG at the given quality. Only replaces
 * the original file if the compressed version is actually smaller.
 * Returns the final filename (may differ from input if the extension changed).
 */
async function compressImageFile(filePath, { quality = 82, maxDimension = 1440 } = {}) {
    try {
        const originalSize = fs.statSync(filePath).size;

        const ext = path.extname(filePath);
        const isJpegOutput = true; // normalize everything to jpeg for consistent, small output
        const tmpPath = `${filePath}.compressed.jpg`;

        await sharp(filePath)
            .rotate() // apply EXIF orientation before stripping metadata
            .resize({ width: maxDimension, height: maxDimension, fit: 'inside', withoutEnlargement: true })
            .jpeg({ quality, mozjpeg: true })
            .toFile(tmpPath);

        const compressedSize = fs.statSync(tmpPath).size;

        if (compressedSize >= originalSize) {
            fs.unlinkSync(tmpPath);
            return path.basename(filePath);
        }

        const finalPath = isJpegOutput && ext.toLowerCase() !== '.jpg'
            ? filePath.slice(0, -ext.length) + '.jpg'
            : filePath;

        fs.renameSync(tmpPath, finalPath);
        if (finalPath !== filePath) fs.unlinkSync(filePath);

        console.log(`🖼️ [IMAGE_COMPRESS] ${path.basename(filePath)}: ${(originalSize / 1024).toFixed(0)}KB -> ${(compressedSize / 1024).toFixed(0)}KB (${((1 - compressedSize / originalSize) * 100).toFixed(1)}% smaller)`);

        return path.basename(finalPath);
    } catch (e) {
        console.error('🚨 [IMAGE_COMPRESS] Failed, keeping original:', e.message);
        return path.basename(filePath);
    }
}

module.exports = { compressImageFile };
