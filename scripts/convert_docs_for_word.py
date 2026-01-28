import os
import re
import html

def convert_markdown_to_html(md_content):
    lines = md_content.split('\n')
    html_output = []

    # Simple state machine
    in_code_block = False
    code_block_lang = ""

    html_output.append('<!DOCTYPE html>')
    html_output.append('<html><head><meta charset="UTF-8">')
    html_output.append('<style>')
    html_output.append('body { font-family: "Calibri", "Arial", sans-serif; font-size: 11pt; line-height: 1.5; color: #000; max-width: 800px; margin: 20px auto; }')
    html_output.append('h1 { font-size: 24pt; color: #2E74B5; border-bottom: 2px solid #2E74B5; padding-bottom: 10px; margin-top: 24pt; }')
    html_output.append('h2 { font-size: 18pt; color: #2E74B5; margin-top: 18pt; }')
    html_output.append('h3 { font-size: 14pt; color: #1F4D78; margin-top: 14pt; }')
    html_output.append('h4 { font-size: 12pt; font-weight: bold; margin-top: 12pt; }')
    html_output.append('p { margin-bottom: 10pt; }')
    html_output.append('ul, ol { margin-bottom: 10pt; }')
    html_output.append('li { margin-bottom: 4pt; }')
    # Styling specifically for Word copy-paste compatibility
    html_output.append('pre { font-family: "Consolas", "Courier New", monospace; font-size: 10pt; background-color: #f5f5f5; padding: 10px; border: 1px solid #ddd; white-space: pre-wrap; word-wrap: break-word; }')
    html_output.append('code { font-family: "Consolas", "Courier New", monospace; color: #c7254e; background-color: #f9f2f4; padding: 2px 4px; border-radius: 4px; }')
    html_output.append('pre code { background-color: transparent; color: inherit; padding: 0; }')
    html_output.append('.mermaid { border: 1px solid #007acc; background-color: #e6f7ff; padding: 15px; border-radius: 5px; margin: 10px 0; }')
    html_output.append('.mermaid-title { color: #007acc; font-weight: bold; font-family: sans-serif; margin-bottom: 5px; }')
    html_output.append('table { border-collapse: collapse; width: 100%; margin-bottom: 15px; }')
    html_output.append('th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }')
    html_output.append('th { background-color: #f2f2f2; color: #333; }')
    html_output.append('blockquote { border-left: 4px solid #ddd; padding-left: 15px; color: #666; font-style: italic; }')
    html_output.append('</style>')
    html_output.append('</head><body>')

    list_stack = [] # Track nested lists 'ul' or 'ol'

    for line in lines:
        stripped_line = line.strip()

        # Handle Code Blocks
        if line.strip().startswith('```'):
            if not in_code_block:
                in_code_block = True
                code_block_lang = line.strip()[3:].strip()
                if code_block_lang == 'mermaid':
                    html_output.append('<div class="mermaid"><div class="mermaid-title">Mermaid Diagram (Copy text to Mermaid Live Editor)</div><pre>')
                else:
                    html_output.append(f'<pre class="{code_block_lang}"><code>')
            else:
                in_code_block = False
                if code_block_lang == 'mermaid':
                     html_output.append('</pre></div>')
                else:
                    html_output.append('</code></pre>')
                code_block_lang = ""
            continue

        if in_code_block:
            # Escape HTML in code blocks
            safe_line = html.escape(line)
            html_output.append(safe_line + '\n')
            continue

        # Close lists if line is empty or header (simplified logic)
        if not line.strip() and list_stack:
            while list_stack:
                html_output.append(f'</{list_stack.pop()}>')

        # Skip empty lines (except closing lists above)
        if not line.strip():
            continue

        # Headers
        if line.startswith('#'):
            level = len(line.split()[0])
            content = line[level:].strip()
            # Basic inline formatting for headers
            content = parse_inline(content)
            html_output.append(f'<h{level}>{content}</h{level}>')

        # Unordered Lists
        elif line.strip().startswith('- ') or line.strip().startswith('* '):
            if not list_stack or list_stack[-1] != 'ul':
                html_output.append('<ul>')
                list_stack.append('ul')
            content = line.strip()[2:]
            content = parse_inline(content)
            html_output.append(f'<li>{content}</li>')

        # Ordered Lists (basic support)
        elif re.match(r'^\d+\.', line.strip()):
            if not list_stack or list_stack[-1] != 'ol':
                html_output.append('<ol>')
                list_stack.append('ol')
            content = re.sub(r'^\d+\.\s*', '', line.strip())
            content = parse_inline(content)
            html_output.append(f'<li>{content}</li>')

        # Blockquotes
        elif line.startswith('> '):
            content = line[2:].strip()
            content = parse_inline(content)
            html_output.append(f'<blockquote>{content}</blockquote>')

        # Tables (Very basic, assumes Markdown table format)
        elif '|' in line and (line.strip().startswith('|') or line.strip().endswith('|')):
             # Check if it's a separator line like |---|---|
            if re.match(r'^\|?[\s-]+\|[\s-]+\|', line.strip()):
                continue

            # Use a simple heuristics to start/end table?
            # Ideally proper parsing, but for now wrap rows in TR/TD
            cols = [c.strip() for c in line.strip().strip('|').split('|')]
            row_html = '<tr>'
            for col in cols:
                row_html += f'<td>{parse_inline(col)}</td>'
            row_html += '</tr>'

            # Note: This is a hacky way to inject tables.
            # A robust parser would track "in_table" state.
            # For simplicity, we just output the row. If previous line wasn't table, we miss <table> tag.
            # But Word is forgiving. Let's wrap in a table for safety if it looks like one.
            if '</table>' not in html_output[-1] and '<tr>' not in html_output[-1] and '<table>' not in html_output[-1]:
                 html_output.append('<table>')

            html_output.append(row_html)

        # Paragraphs
        else:
             # Close table if we were in one (heuristic)
            if html_output and html_output[-1].strip().endswith('</tr>'):
                 html_output.append('</table>')

            content = parse_inline(line)
            html_output.append(f'<p>{content}</p>')

    # Cleanup trailing tags
    while list_stack:
        html_output.append(f'</{list_stack.pop()}>')
    if html_output and html_output[-1].strip().endswith('</tr>'):
        html_output.append('</table>')

    html_output.append('</body></html>')
    return '\n'.join(html_output)

def parse_inline(text):
    # Bold
    text = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', text)
    # Italic
    text = re.sub(r'\*(.*?)\*', r'<i>\1</i>', text)
    # Code
    text = re.sub(r'`(.*?)`', r'<code>\1</code>', text)
    # Links [text](url) -> <a href="url">text</a>
    text = re.sub(r'\[(.*?)\]\((.*?)\)', r'<a href="\2">\1</a>', text)
    return text

def main():
    source_dir = 'docs'
    target_dir = 'docs/word-compatible'

    if not os.path.exists(target_dir):
        os.makedirs(target_dir)

    for filename in os.listdir(source_dir):
        if filename.endswith('.md'):
            filepath = os.path.join(source_dir, filename)
            print(f"Converting {filename}...")

            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()

            html_content = convert_markdown_to_html(content)

            target_filename = filename.replace('.md', '.html')
            target_filepath = os.path.join(target_dir, target_filename)

            with open(target_filepath, 'w', encoding='utf-8') as f:
                f.write(html_content)

    print(f"Conversion complete. Files saved to {target_dir}")

if __name__ == "__main__":
    main()
