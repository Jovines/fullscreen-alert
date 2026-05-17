import Foundation

// MARK: - HTML 生成

func generateHTMLPage(markdown: String) -> String {
    let escapedMarkdown = markdown
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")

    return """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        <script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js"></script>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/atom-one-dark.min.css">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body { margin: 0; padding: 0; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                font-size: 15px;
                line-height: 1.5;
                color: #ffffff;
                background: transparent;
            }
            #content {
                overflow-y: auto;
                overflow-x: hidden;
                padding-right: 8px;
            }
            #content::-webkit-scrollbar { width: 6px; }
            #content::-webkit-scrollbar-track { background: rgba(255, 255, 255, 0.1); border-radius: 3px; }
            #content::-webkit-scrollbar-thumb { background: rgba(255, 255, 255, 0.3); border-radius: 3px; }
            #content::-webkit-scrollbar-thumb:hover { background: rgba(255, 255, 255, 0.5); }
            p { margin: 0 0 8px 0; }
            h1, h2, h3, h4, h5, h6 { margin: 8px 0 4px 0; font-weight: 600; line-height: 1.3; }
            h1 { font-size: 18px; }
            h2 { font-size: 16px; }
            h3 { font-size: 15px; }
            h4 { font-size: 14px; }
            code {
                font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
                font-size: 13px;
                background: rgba(255, 255, 255, 0.15);
                padding: 2px 5px;
                border-radius: 3px;
            }
            pre {
                background: rgba(30, 30, 30, 0.9);
                padding: 10px;
                border-radius: 6px;
                overflow-x: auto;
                margin: 6px 0;
            }
            pre code { background: none; padding: 0; }
            .hljs { background: transparent !important; }
            strong, b { font-weight: 700; }
            em, i { font-style: italic; }
            a { color: #5EB5F7; text-decoration: none; }
            ul, ol { margin: 6px 0; padding-left: 20px; }
            li { margin: 2px 0; }
            table { border-collapse: collapse; margin: 6px 0; font-size: 14px; }
            th, td {
                border: 1px solid rgba(255, 255, 255, 0.15);
                padding: 6px 10px;
                text-align: left;
                transition: background 0.15s ease;
            }
            th {
                background: linear-gradient(180deg, rgba(255, 255, 255, 0.12) 0%, rgba(255, 255, 255, 0.06) 100%);
                font-weight: 600;
                border-bottom: 1px solid rgba(255, 255, 255, 0.2);
            }
            tr:nth-child(even) td { background: rgba(255, 255, 255, 0.03); }
            tr:hover td { background: rgba(255, 255, 255, 0.1); }
            blockquote {
                border-left: 3px solid rgba(255, 255, 255, 0.3);
                padding-left: 12px;
                margin: 6px 0;
                color: rgba(255, 255, 255, 0.85);
            }
            hr { border: none; border-top: 1px solid rgba(255, 255, 255, 0.2); margin: 8px 0; }
        </style>
    </head>
    <body>
        <div id="content"></div>
        <script>
            var markdown = "\(escapedMarkdown)";
            var html = marked.parse(markdown);
            document.getElementById('content').innerHTML = html;

            // 代码高亮
            document.querySelectorAll('pre code').forEach(function(block) {
                hljs.highlightElement(block);
            });

            // 表格列宽调整
            function adjustTableColumns() {
                var tables = document.querySelectorAll('table');
                var maxColWidth = \(Int(Constants.maxTableColumnWidth));

                tables.forEach(function(table) {
                    var rows = table.querySelectorAll('tr');
                    if (rows.length === 0) return;

                    var firstRowCells = rows[0].querySelectorAll('td, th');
                    var colCount = firstRowCells.length;
                    if (colCount === 0) return;

                    var measureSpan = document.createElement('span');
                    measureSpan.style.visibility = 'hidden';
                    measureSpan.style.position = 'absolute';
                    measureSpan.style.whiteSpace = 'nowrap';
                    measureSpan.style.fontSize = '14px';
                    measureSpan.style.fontFamily = '-apple-system, BlinkMacSystemFont, sans-serif';
                    document.body.appendChild(measureSpan);

                    var colWidths = [];
                    for (var col = 0; col < colCount; col++) {
                        var maxContentWidth = 0;
                        for (var r = 0; r < rows.length; r++) {
                            var cells = rows[r].querySelectorAll('td, th');
                            if (cells[col]) {
                                measureSpan.textContent = cells[col].textContent;
                                var textWidth = measureSpan.offsetWidth;
                                if (textWidth > maxContentWidth) maxContentWidth = textWidth;
                            }
                        }
                        colWidths[col] = Math.min(maxContentWidth + 20, maxColWidth);
                    }

                    document.body.removeChild(measureSpan);
                    table.style.tableLayout = 'fixed';
                    var totalWidth = colWidths.reduce(function(a, b) { return a + b; }, 0);
                    table.style.width = totalWidth + 'px';

                    for (var r = 0; r < rows.length; r++) {
                        var cells = rows[r].querySelectorAll('td, th');
                        for (var col = 0; col < cells.length; col++) {
                            cells[col].style.width = colWidths[col] + 'px';
                            cells[col].style.wordWrap = 'break-word';
                            cells[col].style.overflowWrap = 'break-word';
                        }
                    }

                    var container = document.getElementById('content');
                    var containerWidth = container.clientWidth;
                    if (totalWidth > containerWidth) {
                        var wrapper = document.createElement('div');
                        wrapper.style.overflowX = 'auto';
                        wrapper.style.marginBottom = '8px';
                        wrapper.style.width = '100%';
                        table.parentNode.insertBefore(wrapper, table);
                        wrapper.appendChild(table);
                        wrapper.style.paddingBottom = '4px';
                    }
                });
            }

            adjustTableColumns();
        </script>
    </body>
    </html>
    """
}
