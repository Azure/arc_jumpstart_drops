import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import fetch from 'node-fetch';
import fs from 'fs';

class ProfanityEngine {
    constructor(config) {
        this.isTestMode = config?.testMode ?? false;
        this.language = config?.language ?? 'en';
        this.terms = [];
        this.filePath = '';
    }

    /**
    * Initializes the ProfanityEngine by setting the language file path and reading the file content.
    * If an error occurs while reading the file, it logs a warning message and sets the terms array to an empty array.
    */
    async initialize() {
        this.filePath = await this.getLanguageFilePath(this.language);
        try {
            const fileContent = await this.readFileAndSplit(this.filePath);
            const modifiedFileContent = fileContent.map(line => line.replace(/\r/g, ''));
            this.terms = modifiedFileContent;
        } catch (err) {
            if (!this.isTestMode) {
                console.warn('Profanity words issue:', `Error reading file: ${err.message}`);
            }
            this.terms = [];
        }
    }

    /**
     * Gets the file path for the specified language.
     * If the language file does not exist, it logs a warning message and returns the file path for the default 'en' language.
     * @param {string} language - The language code.
     * @returns {Promise<string>} - The file path for the language file.
     */
    async getLanguageFilePath(language) {
        const currentFilePath = fileURLToPath(import.meta.url);
        const dataFolderPath = path.join(path.dirname(currentFilePath), 'data');
        const languageFilePath = path.join(dataFolderPath, `${language}.txt`);
        const fileExists = await this.fileExists(languageFilePath);

        if (!fileExists) {
            if (!this.isTestMode) {
                console.warn('Profanity words issue:', `Warning: The ${language} language file could not be found. Defaulting to 'en' language.`);
            }
            return path.join(dataFolderPath, 'en.txt');
        }

        return languageFilePath;
    }

    /**
     * Checks if a file exists at the specified file path.
     * @param {string} filePath - The file path to check.
     * @returns {Promise<boolean>} - A boolean indicating whether the file exists or not.
     */
    async fileExists(filePath) {
        try {
            await readFile(filePath);
            return true;
        } catch (err) {
            return false;
        }
    }

    /**
     * Reads the content of a file and splits it into an array of terms.
     * If an error occurs while reading the file, it logs a warning message and returns an empty array.
     * @param {string} filePath - The file path to read.
     * @returns {Promise<string[]>} - An array of terms read from the file.
     */
    async readFileAndSplit(filePath) {
        try {
            const fileContent = await readFile(filePath, 'utf8');
            return fileContent.split('\n');
        } catch (err) {
            if (!this.isTestMode) {
                console.warn('Profanity words issue:', err);
            }
            return [];
        }
    }

    /**
     * Checks if a sentence contains any curse words.
     * If the terms array is empty, it initializes the ProfanityEngine.
     * @param {string} sentence - The sentence to check.
     * @returns {Promise<boolean>} - A boolean indicating whether the sentence contains curse words or not.
     */
    async hasCurseWords(content, fileName) {
        if (this.terms.length === 0) {
            await this.initialize();
        }

        if (fileName.endsWith('.json')) {
            const jsonData = JSON.parse(content);
            const jsonString = JSON.stringify(jsonData);
            const words = jsonString.replace(/[^\w\s"]/g, ' ').replace(/\'/g, '').replace(/\"/g, '').split(/\s+/).filter(word => word.trim().length > 0);
            content = words.join(' ');
        }

        const curseWords = [];
        const lines = content.split('\n');
        let sentenceNumber = 0;

        lines.forEach(sentence => {
            sentenceNumber++;
            if (sentence.trim().length === 0) {
                return;
            }

            const cleanedSentence = sentence.replace(/\s{2,}/g, ' ');
            const words = cleanedSentence.split(/\s+/).filter(word => word.trim().length > 0);
            const lowerCasedTerms = this.terms.map(term => term.toLowerCase());
            words.forEach((word, index) => {
                const lowerCasedWord = word.toLowerCase();
                if (lowerCasedTerms.includes(lowerCasedWord)) {
                    console.log('❌ - Curse word found:', lowerCasedWord);
                    curseWords.push({ fileName, word: lowerCasedWord, sentenceNumber });
                }
            });
        });

        return curseWords;
    }

    /**
     * Searches for a term in the terms array.
     * If the terms array is empty, it initializes the ProfanityEngine.
     * @param {string} term - The term to search for.
     * @returns {Promise<boolean>} - A boolean indicating whether the term was found or not.
     */
    async search(term) {
        if (this.terms.length === 0) {
            await this.initialize();
        }

        return this.terms.includes(term);
    }

    /**
     * Checks the content from a URL (markdown content) and validates that there are no profanity words.
     * @param {string} url - The URL of the markdown content to check.
     * @returns {Promise<boolean>} - A boolean indicating whether the content contains profanity words or not.
     */
    async checkURLContentForProfanity(url) {
        try {
            const response = await fetch(url);
            const content = await response.text();
            const engine = new ProfanityEngine();
            await engine.initialize();
            const fileName = url.split('/').pop();
            return await engine.hasCurseWords(content, fileName);
        } catch (err) {
            console.error('Error checking URL content for profanity:', err);
            return false;
        }
    }

    /**
     * Checks the content from a file (markdown content) and validates that there are no profanity words.
     * @param {string} filePath - The path of the file to check.
     * @returns {Promise} - A boolean indicating whether the content contains profanity words or not.
     */
    async checkFileContentForProfanity(filePath) {
        try {
            const content = await readFile(filePath, 'utf-8');
            const filenameWithExtension = path.basename(filePath);
            const engine = new ProfanityEngine();
            await engine.initialize();
            return await engine.hasCurseWords(content, filenameWithExtension);
        } catch (err) {
            console.error('Error checking file content for profanity:', err);
            return false;
        }
    }
}

const engine = new ProfanityEngine();
const urlsOrFilePaths = process.argv.slice(2);
console.log('🚀 - Starting content validation...');

const dropsFilePaths = urlsOrFilePaths.filter(urlOrFilePath => urlOrFilePath.includes('drops/'));
if (dropsFilePaths.length > 1) {
    console.warn('⚠️ - Warning - Multiple Drop JSON files found. Only the first file will be kept.');
    dropsFilePaths.splice(1);
} else if (dropsFilePaths.length === 0) {
    console.warn('⚠️  - Warning - Drop JSON schema not found.');
} else {
    console.log('✅ - Success - Drop JSON schema found.');
    const jsonData = JSON.parse(fs.readFileSync(dropsFilePaths[0], 'utf-8'));
    const source = jsonData.Source;
    console.log(' ℹ️ - Source:', source);
    if (source.includes('arc_jumpstart_drops')) {
        console.log(' ℹ️ - Drop hosted in Arc Jumpstart Drops, no extra fetch.');
    } else {
        console.log(' ℹ️ - Source hosted externally.');
        console.log(' ℹ️ - Attempting to get README or Index.');

        const sourceUrlParts = source.split('/');
        const org = sourceUrlParts[3];
        const repo = sourceUrlParts[4];
        console.log(' ℹ️ - Org:', org);
        console.log(' ℹ️ - Repo:', repo);

        const readmeUrl = `https://raw.githubusercontent.com/${org}/${repo}/main/README.md`;
        console.log(' ℹ️ - README URL:', readmeUrl);
        const readmeResponse = await fetch(readmeUrl);
        if (readmeResponse.ok) {
            console.log('✅ - Success - README.md found.');
            urlsOrFilePaths.push(readmeUrl);
        } else {
            console.log(' ℹ️ - README.md not found. Attempting to get Index.md.');
            const indexUrl = `https://raw.githubusercontent.com/${org}/${repo}/main/index.md`;
            console.log(' ℹ️ - Index URL:', indexUrl);
            const indexResponse = await fetch(indexUrl);
            if (indexResponse.ok) {
                console.log('✅ - Success - Index.md found.');
                urlsOrFilePaths.push(indexUrl);
            } else {
                console.log(' ℹ️ - Index.md not found. Attempting to get _index.md.');
                const indexUnderUrl = `https://raw.githubusercontent.com/${org}/${repo}/main/_index.md`;
                console.log(' ℹ️ - Index URL:', indexUnderUrl);
                const indexUnderResponse = await fetch(indexUnderUrl);
                if (indexUnderResponse.ok) {
                    console.log('✅ - Success - _index.md found.');
                    urlsOrFilePaths.push(indexUnderUrl);
                } else {
                    console.log('❌ - Error - README.md, Index.md, and _index.md not found.');
                }
            }
        }
    }
}

console.log(' ℹ️ - Checking the following URLs or file paths: ', urlsOrFilePaths);

// Filter for files under the 'drops/' folder and exclude common binary and picture file extensions
const validExtensions = ['.txt', '.md', '.json']; // Add more text-based extensions as needed
const validDropsFilePaths = urlsOrFilePaths.filter(urlOrFilePath => {
  return urlOrFilePath.includes('drops/') && validExtensions.some(ext => urlOrFilePath.endsWith(ext));
});

const excludedFiles = urlsOrFilePaths.filter(urlOrFilePath => !validDropsFilePaths.includes(urlOrFilePath));
if (excludedFiles.length > 0) {
    console.log(' ℹ️ - The following files were left out due to invalid extensions: ', excludedFiles);
}

const promises = validDropsFilePaths.map(urlOrFilePath => {
    if (urlOrFilePath.startsWith('http')) {
        return engine.checkURLContentForProfanity(urlOrFilePath);
    } else {
        return engine.checkFileContentForProfanity(urlOrFilePath);
    }
});

Promise.all(promises)
    .then(results => {
        const curseWords = results.flat();
        if (curseWords.length > 0) {
            console.warn('❌ - Error - Validation failed, curse words found');
            console.table(curseWords, ['fileName', 'word', 'sentenceNumber']);
            return process.exit(1);
        } else {
            console.log('✅ - Success - Content validation passed.');
            console.log('🚀 - Finished content validation...');
            return process.exit(0);
        }
    });
