const fs = require('fs');
const path = require('path');
const exec = require('child_process').execSync;

const auxDir = "./";
const dropsDir = path.join(auxDir, 'drops');
const files = fs.readdirSync(dropsDir).filter(file => file.endsWith('.json'));

let changesFound = false;
let changedDrops = [];
let resultTableData = [];

const getCommitDataFromGitHub = (owner, repo, commitHash) => {
    const commitDateCommand = `curl -s https://api.github.com/repos/${owner}/${repo}/git/commits/${commitHash}`;
    const commitDateResponse = exec(commitDateCommand).toString().trim();
    return JSON.parse(commitDateResponse);
};

const getLatestCommit = (owner, repo, sourceUrl) => {
    const pathAfterRepo = sourceUrl.split('/');
    let commitUrl = `https://api.github.com/repos/${owner}/${repo}/commits`;
    if (pathAfterRepo.length > 5 && pathAfterRepo.slice(5).join('/') !== 'tree/main' && pathAfterRepo.slice(5).join('/') !== 'tree/master') {
        commitUrl += `?path=${pathAfterRepo.slice(5).join('/').replace('tree/master', '').replace('tree/main', '')}`;
    }
    const commitResponse = exec(`curl -s ${commitUrl}`).toString().trim();
    if(commitResponse === '[]') {
        console.log(`No commits found for ${sourceUrl}`);
        return null;
    }
    return JSON.parse(commitResponse)[0];
};

const processFile = (file) => {
    const filePath = path.join(dropsDir, file);
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const lastModified = new Date(data.LastModified);
    const sourceUrl = data.Source;
    const repoUrlMatch = sourceUrl.match(/https:\/\/github\.com\/([^/]+)\/([^/]+)/);

    if (!repoUrlMatch) return;

    const [_, owner, repo] = repoUrlMatch;

    if (owner === 'Azure' && repo === 'arc_jumpstart_drops') {
        const gitCommand = `git log -n 1 --format=%H -- ${filePath}`;
        const commitHash = exec(gitCommand).toString().trim();
        const commitData = getCommitDataFromGitHub(owner, repo, commitHash);
        const commitDate = commitData.author?.date ? new Date(commitData.author.date) : null;
        
        if (commitDate && lastModified < commitDate) {
            changesFound = true;
            changedDrops.push(file);
        }
        
        resultTableData.push({
            title: data.Title,
            commit: commitHash,
            lastModified: lastModified,
            lastCommitDate: commitDate || 'Warning',
            modified: commitDate ? (lastModified < commitDate ? 'Yes' : 'No') : 'Warning'
        });
    } else {
        const latestCommit = getLatestCommit(owner, repo, sourceUrl);
        const commitDate = new Date(latestCommit.commit.author.date);

        if (lastModified < commitDate) {
            changesFound = true;
            changedDrops.push(file);
        }

        resultTableData.push({
            title: data.Title,
            commit: latestCommit.sha,
            lastModified: lastModified,
            lastCommitDate: commitDate,
            modified: lastModified < commitDate ? 'Yes' : 'No'
        });
    }
};

const processFilesAsync = async () => {
    for (const file of files) {
        await new Promise(resolve => setTimeout(resolve, 30000)); // Wait 30 seconds due to GitHub API rate limits (60 requests per hour for unauthenticated requests)
        await processFile(file);
    }
};

processFilesAsync()
    .then(() => {
        console.table(resultTableData);
        console.log(`\n ----- Changed Drops ------ \n`);
        console.log(changedDrops.join('\n'));
        process.exit(changesFound ? 1 : 0);
    })
    .catch(error => {
        console.table(resultTableData);
        console.error(error);
        process.exit(1);
    });