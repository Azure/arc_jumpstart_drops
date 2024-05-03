import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import fetch from 'node-fetch';

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
            this.terms = fileContent;
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
            return await engine.hasCurseWords(content, "_index.md");
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

const promises = urlsOrFilePaths.map(urlOrFilePath => {
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
    } else {
      console.log('✅ - Success - Content validation passed.');
    }
  })
  .catch(error => {
    console.error('❌ - Error - Content validation failed:', error);
  });