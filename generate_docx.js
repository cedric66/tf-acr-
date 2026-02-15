const {
    Document,
    Packer,
    Paragraph,
    TextRun,
    Table,
    TableRow,
    TableCell,
    TableOfContents,
    HeadingLevel,
    AlignmentType,
    PageBreak,
    BorderStyle,
    WidthType,
    ShadingType,
    LevelFormat,
    Footer,
    Header,
    PageNumber,
    VerticalAlign
} = require("docx");
const fs = require("fs");

// Enterprise Design Constants
const CONTENT_WIDTH = 9360; 
const PRIMARY_BLUE = "2B579A"; // Classic Enterprise Blue
const SECONDARY_BLUE = "D9E5F3"; // Light Background
const ACCENT_GRAY = "444444"; // For softer headings
const BORDER_COLOR = "AEBED5";

// Styles Definition
const styles = {
    paragraphStyles: [
        {
            id: "Normal",
            name: "Normal",
            run: { size: 22, font: "Arial" }, // 11pt for better information density
            paragraph: { spacing: { line: 276, before: 120, after: 120 } }
        },
        {
            id: "Heading1",
            name: "Heading 1",
            basedOn: "Normal",
            next: "Normal",
            quickFormat: true,
            run: { size: 36, bold: true, color: PRIMARY_BLUE, font: "Arial" },
            paragraph: { spacing: { before: 480, after: 240 }, outlineLevel: 0, borders: { bottom: { style: BorderStyle.SINGLE, size: 6, color: PRIMARY_BLUE } } }
        },
        {
            id: "Heading2",
            name: "Heading 2",
            basedOn: "Normal",
            next: "Normal",
            quickFormat: true,
            run: { size: 28, bold: true, color: ACCENT_GRAY, font: "Arial" },
            paragraph: { spacing: { before: 360, after: 180 }, outlineLevel: 1 }
        },
        {
            id: "Heading3",
            name: "Heading 3",
            basedOn: "Normal",
            next: "Normal",
            quickFormat: true,
            run: { size: 24, bold: true, font: "Arial", color: "666666" },
            paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 2 }
        },
        {
            id: "Code",
            name: "Code",
            run: { font: "Consolas", size: 18, color: "000000" },
            paragraph: {
                spacing: { before: 0, after: 0 },
                shading: { fill: "F8F9FA", type: ShadingType.CLEAR },
                indent: { left: 400 },
                borders: {
                    left: { style: BorderStyle.SINGLE, size: 12, color: PRIMARY_BLUE },
                }
            }
        }
    ]
};

function createBorderedTable(rows, columnWidths) {
    const border = { style: BorderStyle.SINGLE, size: 2, color: BORDER_COLOR };
    const borders = { top: border, bottom: border, left: border, right: border };

    return new Table({
        width: { size: CONTENT_WIDTH, type: WidthType.DXA },
        columnWidths: columnWidths,
        rows: rows.map(row => new TableRow({
            children: row.map((cell, i) => new TableCell({
                borders,
                width: { size: columnWidths[i], type: WidthType.DXA },
                margins: { top: 100, bottom: 100, left: 150, right: 150 },
                shading: cell.header ? { fill: SECONDARY_BLUE, type: ShadingType.CLEAR } : undefined,
                verticalAlign: VerticalAlign.CENTER,
                children: [new Paragraph({ 
                    children: parseInlineFormatting(cell.text, cell.header) 
                })]
            }))
        }))
    });
}

function parseInlineFormatting(text, forceBold = false) {
    const parts = [];
    let lastIndex = 0;
    const boldRegex = /\*\*(.*?)\*\*/g;
    let match;

    while ((match = boldRegex.exec(text)) !== null) {
        if (match.index > lastIndex) {
            parts.push(new TextRun({ text: text.substring(lastIndex, match.index), bold: forceBold }));
        }
        parts.push(new TextRun({ text: match[1], bold: true }));
        lastIndex = boldRegex.lastIndex;
    }

    if (lastIndex < text.length) {
        parts.push(new TextRun({ text: text.substring(lastIndex), bold: forceBold }));
    }

    return parts.length > 0 ? parts : [new TextRun({ text: text, bold: forceBold })];
}

async function generate() {
    const doc = new Document({
        styles: styles,
        numbering: {
            config: [{
                reference: "bullets",
                levels: [{
                    level: 0,
                    format: LevelFormat.BULLET,
                    text: "•",
                    alignment: AlignmentType.LEFT,
                    style: { paragraph: { indent: { left: 720, hanging: 360 } } }
                }]
            }]
        },
        sections: [{
            properties: {
                page: {
                    size: { width: 12240, height: 15840 },
                    margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
                }
            },
            headers: {
                default: new Header({
                    children: [
                        new Paragraph({
                            alignment: AlignmentType.RIGHT,
                            children: [new TextRun({ text: "AKS Enterprise Migration Strategy", color: "AAAAAA", size: 18, italic: true })]
                        })
                    ]
                })
            },
            footers: {
                default: new Footer({
                    children: [
                        new Paragraph({
                            alignment: AlignmentType.CENTER,
                            children: [
                                new TextRun({ text: "Confidential - For Internal Use Only", color: "AAAAAA", size: 16 }),
                                new TextRun({ text: "\t\tPage ", color: "AAAAAA", size: 18 }),
                                new TextRun({ children: [PageNumber.CURRENT], color: "AAAAAA", size: 18 })
                            ]
                        })
                    ]
                })
            },
            children: [
                // COVER PAGE
                new Paragraph({ spacing: { before: 3000 }, alignment: AlignmentType.CENTER, children: [new TextRun({ text: "AKS Spot Node Migration Guide & Rollout Strategy", size: 56, bold: true, color: PRIMARY_BLUE })] }),
                new Paragraph({ spacing: { after: 1200 }, alignment: AlignmentType.CENTER, children: [new TextRun({ text: "Cloud Infrastructure Architecture", size: 32, color: ACCENT_GRAY })] }),
                
                createBorderedTable([
                    [{ text: "Document ID", header: true }, { text: "ARCH-AKS-2026-001" }],
                    [{ text: "Status", header: true }, { text: "Approved / Production Ready" }],
                    [{ text: "Version", header: true }, { text: "1.0.0" }],
                    [{ text: "Date", header: true }, { text: "February 15, 2026" }]
                ], [3000, 6360]),

                new Paragraph({ children: [new PageBreak()] }),

                // TOC
                new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("1. Executive Table of Contents")] }),
                new TableOfContents("Table of Contents", { hyperlink: true, headingStyleRange: "1-3" }),
                
                new Paragraph({ children: [new PageBreak()] }),

                // METADATA
                new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("2. Document Control")] }),
                new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("2.1 Revision History")] }),
                createBorderedTable([
                    [{ text: "Ver.", header: true }, { text: "Date", header: true }, { text: "Description", header: true }, { text: "Approver", header: true }],
                    [{ text: "1.0" }, { text: "2026-02-15" }, { text: "Initial architecture baselining and rollout definition." }, { text: "Principal Architect" }]
                ], [800, 1500, 5060, 2000]),

                new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("2.2 Distribution List")] }),
                createBorderedTable([
                    [{ text: "Role", header: true }, { text: "Responsibility", header: true }],
                    [{ text: "Cloud Operations" }, { text: "Execution & Monitoring" }],
                    [{ text: "SRE Team" }, { text: "Reliability Engineering & Observability" }],
                    [{ text: "DevOps Teams" }, { text: "Application Workload Onboarding" }]
                ], [3000, 6360]),

                new Paragraph({ children: [new PageBreak()] }),

                // CONTENT
                ...parseMarkdownFile("docs/migration/MIGRATION_GUIDE_AKS_SPOT.md"),
                new Paragraph({ children: [new PageBreak()] }),
                ...parseMarkdownFile("docs/migration/MIGRATION_GUIDE_DEVOPS.md"),
                new Paragraph({ children: [new PageBreak()] }),
                ...parseMarkdownFile("docs/migration/FLEET_ROLLOUT_STRATEGY.md"),
                new Paragraph({ children: [new PageBreak()] }),
                ...parseMarkdownFile("docs/migration/GAP_ANALYSIS_300_CLUSTERS.md"),
                new Paragraph({ children: [new PageBreak()] }),
                ...parseMarkdownFile("docs/migration/PROJECT_GAP_ANALYSIS.md")
            ]
        }]
    });

    const buffer = await Packer.toBuffer(doc);
    fs.writeFileSync("AKS_Enterprise_Migration_Guide.docx", buffer);
    console.log("Professional document generated: AKS_Enterprise_Migration_Guide.docx");
}

function parseMarkdownFile(filePath) {
    let content = fs.readFileSync(filePath, "utf-8");
    
    // Professional sanitization: Remove icons and replace with text markers
    content = content.replace(/✅/g, "[OK]");
    content = content.replace(/❌/g, "[ERROR]");
    content = content.replace(/⚠️/g, "CAUTION:");
    content = content.replace(/🔴/g, "CRITICAL:");
    content = content.replace(/🟡/g, "MEDIUM:");
    content = content.replace(/🟢/g, "LOW:");
    content = content.replace(/🔍/g, "");
    content = content.replace(/🗺️/g, "");
    content = content.replace(/🏰/g, "");
    content = content.replace(/📊/g, "");
    content = content.replace(/📋/g, "");
    content = content.replace(/🎯/g, "");
    content = content.replace(/🔧/g, "");
    content = content.replace(/📝/g, "");
    content = content.replace(/🚨/g, "INCIDENT:");
    content = content.replace(/🏰/g, "GOVERNANCE:");
    content = content.replace(/🏰/g, "GOVERNANCE:");

    const lines = content.split("\n");
    const elements = [];
    let inCodeBlock = false;
    let codeContent = [];
    let inTable = false;
    let tableRows = [];

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const trimmed = line.trim();

        if (trimmed.startsWith("```")) {
            if (inCodeBlock) {
                while (codeContent.length > 0 && codeContent[0].trim() === "") codeContent.shift();
                while (codeContent.length > 0 && codeContent[codeContent.length - 1].trim() === "") codeContent.pop();
                
                codeContent.forEach((codeLine) => {
                    elements.push(new Paragraph({ 
                        style: "Code", 
                        children: [new TextRun({ text: codeLine })] 
                    }));
                });
                
                // Add closing spacing for the block
                elements.push(new Paragraph({ spacing: { after: 240 } }));
                
                codeContent = [];
                inCodeBlock = false;
            } else {
                inCodeBlock = true;
            }
            continue;
        }

        if (inCodeBlock) {
            codeContent.push(line);
            continue;
        }

        if (trimmed.startsWith("|") && trimmed.includes("|")) {
            if (trimmed.includes("---")) continue; 
            const actualCells = trimmed.startsWith("|") ? trimmed.split("|").slice(1, -1).map(c => c.trim()) : trimmed.split("|").map(c => c.trim());
            tableRows.push(actualCells);
            inTable = true;
            continue;
        } else if (inTable) {
            if (tableRows.length > 0) {
                const colCount = tableRows[0].length;
                const colWidth = Math.floor(CONTENT_WIDTH / colCount);
                elements.push(createBorderedTable(
                    tableRows.map((row, idx) => row.map(cell => ({ text: cell, header: idx === 0 }))),
                    Array(colCount).fill(colWidth)
                ));
            }
            tableRows = [];
            inTable = false;
        }

        if (trimmed.startsWith("# ")) {
            elements.push(new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(trimmed.substring(2))] }));
        } else if (trimmed.startsWith("## ")) {
            elements.push(new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(trimmed.substring(3))] }));
        } else if (trimmed.startsWith("### ")) {
            elements.push(new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(trimmed.substring(4))] }));
        } else if (trimmed.startsWith("- ") || trimmed.startsWith("* ")) {
            let listText = trimmed.substring(2);
            if (listText.startsWith("[ ] ")) {
                listText = "□ " + listText.substring(4);
            } else if (listText.startsWith("[x] ") || listText.startsWith("[X] ")) {
                listText = "☑ " + listText.substring(4);
            }
            elements.push(new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: parseInlineFormatting(listText) }));
        } else if (/^\d+\.\s/.test(trimmed)) {
            elements.push(new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: parseInlineFormatting(trimmed.replace(/^\d+\.\s/, "")) }));
        } else if (trimmed.length > 0 && !trimmed.startsWith("---") && !trimmed.startsWith(">")) {
            elements.push(new Paragraph({ children: parseInlineFormatting(trimmed) }));
        }
    }

    if (inTable && tableRows.length > 0) {
        const colCount = tableRows[0].length;
        const colWidth = Math.floor(CONTENT_WIDTH / colCount);
        elements.push(createBorderedTable(tableRows.map((row, idx) => row.map(cell => ({ text: cell, header: idx === 0 }))), Array(colCount).fill(colWidth)));
    }

    return elements;
}

generate().catch(console.error);
