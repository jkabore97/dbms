const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  LevelFormat, PageBreak, convertInchesToTwip,
} = require('docx');

// A4 portrait, 1" margins -> usable width in DXA
const W = 9026;
const TEAL = '0D7A70';
const TEAL_DARK = '0A5A53';
const GREY = '5A6B6A';
const RULE = 'D6E2E0';
const BAND = 'EEF5F4';

// ---------------------------------------------------------------- helpers

const p = (text, opts = {}) => new Paragraph({
  spacing: { after: opts.after ?? 140, line: 276 },
  alignment: opts.align,
  children: [new TextRun({
    text,
    font: 'Calibri',
    size: opts.size ?? 21,          // half-points: 21 = 10.5pt
    color: opts.color ?? '1A1A1A',
    bold: opts.bold,
    italics: opts.italics,
  })],
});

/** A paragraph mixing bold lead-in and normal text. */
const pRich = (runs, opts = {}) => new Paragraph({
  spacing: { after: opts.after ?? 140, line: 276 },
  children: runs.map((r) => new TextRun({
    text: r.t,
    font: 'Calibri',
    size: opts.size ?? 21,
    color: r.color ?? opts.color ?? '1A1A1A',
    bold: r.b,
    italics: r.i,
  })),
});

const h1 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_1,
  spacing: { before: 380, after: 160 },
  border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: TEAL, space: 6 } },
  children: [new TextRun({ text, font: 'Cambria', size: 30, bold: true, color: TEAL_DARK })],
});

const h2 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_2,
  spacing: { before: 260, after: 100 },
  children: [new TextRun({ text, font: 'Cambria', size: 24, bold: true, color: '1A1A1A' })],
});

const bullet = (text, opts = {}) => new Paragraph({
  numbering: { reference: 'puces', level: 0 },
  spacing: { after: 80, line: 276 },
  children: [new TextRun({
    text, font: 'Calibri', size: 21, color: '1A1A1A', bold: opts.bold,
  })],
});

const bulletRich = (runs) => new Paragraph({
  numbering: { reference: 'puces', level: 0 },
  spacing: { after: 80, line: 276 },
  children: runs.map((r) => new TextRun({
    text: r.t, font: 'Calibri', size: 21, color: '1A1A1A', bold: r.b, italics: r.i,
  })),
});

const numbered = (text) => new Paragraph({
  numbering: { reference: 'chiffres', level: 0 },
  spacing: { after: 80, line: 276 },
  children: [new TextRun({ text, font: 'Calibri', size: 21, color: '1A1A1A' })],
});

const cell = (text, { widths, bold, shade, color, align } = {}) => new TableCell({
  width: { size: widths, type: WidthType.DXA },
  shading: shade ? { type: ShadingType.CLEAR, fill: shade, color: 'auto' } : undefined,
  margins: { top: 90, bottom: 90, left: 130, right: 130 },
  children: [new Paragraph({
    alignment: align,
    spacing: { after: 0, line: 260 },
    children: [new TextRun({
      text, font: 'Calibri', size: 20, bold, color: color ?? '1A1A1A',
    })],
  })],
});

/** cols: array of DXA widths. rows: array of arrays of strings. */
const table = (cols, header, rows) => new Table({
  columnWidths: cols,
  width: { size: W, type: WidthType.DXA },
  borders: {
    top: { style: BorderStyle.SINGLE, size: 4, color: RULE },
    bottom: { style: BorderStyle.SINGLE, size: 4, color: RULE },
    left: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    right: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    insideHorizontal: { style: BorderStyle.SINGLE, size: 4, color: RULE },
    insideVertical: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
  },
  rows: [
    new TableRow({
      tableHeader: true,
      children: header.map((t, i) =>
        cell(t, { widths: cols[i], bold: true, shade: BAND, color: TEAL_DARK })),
    }),
    ...rows.map((r) => new TableRow({
      children: r.map((t, i) => cell(t, { widths: cols[i] })),
    })),
  ],
});

/** A tinted callout block. */
const callout = (title, lines) => new Table({
  columnWidths: [W],
  width: { size: W, type: WidthType.DXA },
  borders: {
    top: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    bottom: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    left: { style: BorderStyle.SINGLE, size: 18, color: TEAL },
    right: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    insideHorizontal: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    insideVertical: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
  },
  rows: [new TableRow({
    children: [new TableCell({
      width: { size: W, type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, fill: BAND, color: 'auto' },
      margins: { top: 170, bottom: 170, left: 220, right: 200 },
      children: [
        new Paragraph({
          spacing: { after: 90 },
          children: [new TextRun({
            text: title, font: 'Cambria', size: 22, bold: true, color: TEAL_DARK,
          })],
        }),
        ...lines.map((t, i) => new Paragraph({
          spacing: { after: i === lines.length - 1 ? 0 : 90, line: 276 },
          children: [new TextRun({ text: t, font: 'Calibri', size: 21, color: '1A1A1A' })],
        })),
      ],
    })],
  })],
});

const spacer = (h = 200) => new Paragraph({ spacing: { after: h }, children: [] });


module.exports = {
  W, TEAL, TEAL_DARK, GREY, RULE, BAND,
  p, pRich, h1, h2, bullet, bulletRich, numbered, cell, table, callout, spacer,
};
