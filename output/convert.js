const mammoth = require("mammoth");
const fs = require("fs");
const path = require("path");

const dir = "/workspace/supportFiles/upload-1779782092704-2cf73096";
const files = fs.readdirSync(dir);
const docx = files.find(f => f.endsWith(".docx"));
if (!docx) { console.error("No .docx found"); process.exit(1); }
const input = path.join(dir, docx);
const output = "/workspace/output/converted.html";

mammoth.convertToHtml({ path: input })
  .then(result => {
    const title = "Requirements Definition Template";
    const html = `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>${title}</title>
<style>
body { font-family: "Yu Gothic", "Meiryo", "Hiragino Sans", sans-serif; max-width: 960px; margin: 2em auto; padding: 0 1em; line-height: 1.6; color: #222; }
table { border-collapse: collapse; margin: 1em 0; width: 100%; }
table, th, td { border: 1px solid #999; padding: 6px 10px; vertical-align: top; }
th { background: #f0f0f0; }
h1, h2, h3 { border-bottom: 1px solid #ddd; padding-bottom: 4px; }
img { max-width: 100%; }
</style>
</head>
<body>
${result.value}
</body>
</html>`;
    fs.writeFileSync(output, html, "utf8");
    console.log("OK ->", output);
    console.log("HTML body length:", result.value.length);
    console.log("Conversion messages:", result.messages.length);
  })
  .catch(err => {
    console.error("ERROR:", err.message);
    process.exit(1);
  });
