const mammoth = require("mammoth");
const fs = require("fs");
const path = require("path");

const input = process.argv[2];
const output = process.argv[3];

mammoth.convertToHtml({ path: input })
  .then(result => {
    const html = `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>${path.basename(input)}</title>
<style>
body { font-family: "Yu Gothic", "Meiryo", sans-serif; max-width: 960px; margin: 2em auto; padding: 0 1em; line-height: 1.6; color: #222; }
table { border-collapse: collapse; margin: 1em 0; }
table, th, td { border: 1px solid #999; padding: 6px 10px; }
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
    console.log("OK: wrote", output);
    if (result.messages.length) {
      console.log("Messages:", result.messages.length);
    }
  })
  .catch(err => {
    console.error("ERROR:", err.message);
    process.exit(1);
  });
