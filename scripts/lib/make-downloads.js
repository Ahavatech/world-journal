// Builds the Word templates the journal offers: manuscript, cover letter, copyright and publication agreement (ojs/client-content/downloads/),
// and the award certificate (ojs/client-content/internal/, not published). Run: NODE_PATH=$(npm root -g) node scripts/lib/make-downloads.js
// Nothing here states a fact the client has not given: unknown names are blank lines to fill in; the agreement was approved by the client on 2026-11-14 and keeps two blanks for the journal (publisher's legal name, governing law).
const fs = require('fs');
const path = require('path');
const d = require('docx');
const { Document, Packer, Paragraph, TextRun, AlignmentType, BorderStyle, Table, TableRow, TableCell, WidthType, ShadingType, ImageRun, PageOrientation, HeadingLevel, Footer, PageNumber } = d;
const root = path.resolve(__dirname, '..', '..');
const FONT = 'Times New Roman';
const JOURNAL = 'World Open Research Journal';
const run = (t, o = {}) => new TextRun({ text: t, font: FONT, size: 24, ...o });
const para = (t, o = {}) => new Paragraph({ spacing: { after: 160, line: 360 }, ...o, children: Array.isArray(t) ? t : [run(t)] });
const head = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 280, after: 120 }, keepNext: true, children: [run(t, { bold: true, size: 26 })] });
const blank = (label) => para([run(label + ': ', { bold: true }), run('______________________________________')]);
const note = (t) => new Paragraph({ spacing: { after: 160 }, shading: { type: ShadingType.CLEAR, fill: 'F2F2F2', color: 'auto' }, border: { top: { style: BorderStyle.SINGLE, size: 4, color: '999999', space: 4 }, bottom: { style: BorderStyle.SINGLE, size: 4, color: '999999', space: 4 } }, children: [run(t, { italics: true, size: 21 })] });
const styles = { default: { document: { run: { font: FONT, size: 24 } } }, paragraphStyles: [{ id: 'Heading1', name: 'heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { font: FONT, size: 26, bold: true }, paragraph: { spacing: { before: 280, after: 120 }, keepNext: true, outlineLevel: 0 } }] };
const footer = (label) => ({ default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [run(`${JOURNAL}: ${label}   |   page `, { size: 18 }), new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 18 })] })] }) });
const page = { size: { width: 11906, height: 16838 }, margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } };
const out = (dir, name, doc) => Packer.toBuffer(doc).then((b) => { fs.mkdirSync(path.join(root, dir), { recursive: true }); fs.writeFileSync(path.join(root, dir, name), b); console.log('wrote', dir + '/' + name); });
const rule = () => new Paragraph({ border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: '000000', space: 1 } }, spacing: { after: 160 }, children: [] });

// ---------------- manuscript template ----------------
const ms = [
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 60 }, children: [run(JOURNAL.toUpperCase(), { bold: true, size: 28 })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 200 }, children: [run('Manuscript template', { size: 24 })] }),
  note('How to use this template. Prepare your manuscript in Microsoft Word (.doc or .docx) in Times New Roman, size 12, in English. Replace every line in square brackets with your own text, keep the headings, and delete these grey instruction boxes before you submit. The journal uses double-blind review: page 1 (the title page) is entered in the submission system and must not be inside the anonymised manuscript file. Upload the title page as a separate file and delete page 1 from the manuscript file.'),
  head('PART A. TITLE PAGE (upload separately; not in the anonymised file)'),
  blank('Title of the article'),
  blank('Running title (short)'),
  para('Authors, affiliations and ORCID iD (one block per author, in the order they should appear):'),
  blank('Author 1: full name'), blank('Affiliation (department, institution, city, country)'), blank('Email'), blank('ORCID iD (optional)'),
  blank('Author 2 (copy this block for each further author)'),
  blank('Corresponding author (name and email)'),
  blank('Article type (for example Original Research, Review)'),
  new Paragraph({ pageBreakBefore: true, spacing: { after: 160 }, children: [run('PART B. ANONYMISED MANUSCRIPT', { bold: true, size: 26 })] }),
  note('Do not put author names, affiliations or acknowledgements that could identify the authors anywhere in Part B. Refer to your own earlier work in the third person ("Smith (2021) showed…").'),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 200, after: 200 }, children: [run('[Title of the article]', { bold: true, size: 30 })] }),
  head('Abstract'),
  note('One paragraph that states the problem, the method, the main results and the conclusion. Do not cite references in the abstract.'),
  para('[Abstract text]'),
  para([run('Keywords: ', { bold: true }), run('[keyword one; keyword two; keyword three; keyword four]')]),
  head('1. Introduction'), para('[Background, the gap in the literature, and the aim of the study.]'),
  head('2. Methods'), para('[Design, participants or materials, data collection, analysis, and enough detail for another researcher to repeat the work. State ethics approval here if it applies.]'),
  head('3. Results'), para('[Report the findings. Number each table and figure and refer to it in the text. Give each table and figure a short caption. Put tables in the text, not as images.]'),
  head('4. Discussion'), para('[Interpret the results, compare them with earlier work, and state the limitations.]'),
  head('5. Conclusion'), para('[The main conclusion and its significance, in a few sentences.]'),
  head('Declarations'),
  para([run('Author contributions: ', { bold: true }), run('[Say who did what. This can be added after review if it would identify the authors.]')]),
  para([run('Funding: ', { bold: true }), run('[Name the funder and grant number, or write "None".]')]),
  para([run('Conflicts of interest: ', { bold: true }), run('[State any, or write "The authors declare no conflict of interest."]')]),
  para([run('Ethics approval: ', { bold: true }), run('[Name the approving body and reference, or write "Not applicable".]')]),
  para([run('Data availability: ', { bold: true }), run('[Say where the data can be found, or why they cannot be shared.]')]),
  para([run('Acknowledgements: ', { bold: true }), run('[Add after review if it would identify the authors.]')]),
  head('References'),
  note('Use one consistent reference style throughout. Every reference cited in the text must be listed here, and every listed reference must be cited. Give a DOI or web address where one exists.'),
  para('[1] Author, A. A., & Author, B. B. (Year). Title of the article. Journal Name, volume(issue), pages. https://doi.org/...'),
];
const manuscript = new Document({ creator: JOURNAL, title: 'Manuscript template', styles, sections: [{ properties: { page }, footers: footer('manuscript template'), children: ms }] });

// ---------------- cover letter ----------------
const cl = [
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 60 }, children: [run('COVER LETTER', { bold: true, size: 28 })] }),
  note('Each submission must be accompanied by a cover letter confirming the originality of the work, its significance, and its suitability for publication in the journal. Replace the lines in square brackets, delete this box, and upload the letter as a supplementary file with your submission.'),
  blank('Date'),
  para([run('To: ', { bold: true }), run('The Editor-in-Chief, ' + JOURNAL)]),
  para([run('Subject: ', { bold: true }), run('Submission of the manuscript "[title of the article]" (article type: [Original Research / Review / other])')]),
  para('Dear Editor,'),
  para('I submit the manuscript named above for consideration in the ' + JOURNAL + '.'),
  para([run('Originality. ', { bold: true }), run('[Confirm that the work is original, has not been published before, and is not under consideration by any other journal.]')]),
  para([run('Significance. ', { bold: true }), run('[In two or three sentences, say what the study contributes and why it matters to the journal\'s readers.]')]),
  para([run('Suitability. ', { bold: true }), run('[Say why the manuscript fits the aims and scope of the journal.]')]),
  para([run('Authors and approval. ', { bold: true }), run('[Confirm that all authors have read and approved the manuscript and agree to its submission, and that the author list is complete.]')]),
  para([run('Ethics and conflicts of interest. ', { bold: true }), run('[Confirm that the research followed the relevant ethical standards, and state any conflict of interest, or write that there is none.]')]),
  para([run('Format. ', { bold: true }), run('[Confirm that the manuscript follows the journal\'s manuscript template: Times New Roman, size 12, Word format.]')]),
  para('Thank you for considering the manuscript.'),
  para('Yours sincerely,'),
  blank('Name of the corresponding author'), blank('Affiliation'), blank('Email'), blank('Signature (optional)'),
];
const cover = new Document({ creator: JOURNAL, title: 'Cover letter template', styles, sections: [{ properties: { page }, footers: footer('cover letter template'), children: cl }] });

// ---------------- copyright and publication agreement ----------------
const cl2 = (n, t, b) => [head(`${n}. ${t}`), para(b)];
const ag = [
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 60 }, children: [run('COPYRIGHT AND PUBLICATION AGREEMENT', { bold: true, size: 28 })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 200 }, children: [run(JOURNAL, { size: 24 })] }),
  para('This agreement is made between the author or authors named below ("the Author") and [legal name of the publisher of the ' + JOURNAL + '] ("the Journal"), about the article described below ("the Article").'),
  blank('Title of the Article'), blank('Name of the corresponding author'), blank('Names of all authors'), blank('Submission number (if known)'),
  ...cl2(1, 'The Author\'s promises', 'The Author confirms that the Article is original and has not been published elsewhere or submitted elsewhere at the same time; that all the authors have approved it and agree to this agreement; that it does not infringe any copyright or other right of any other person; that any material of other people in it (such as figures, tables or long quotations) is used with permission, which the Author will supply on request; and that the research was carried out in line with the ethical standards that apply to it, as stated in the Article.'),
  ...cl2(2, 'The Author keeps copyright', 'The Author keeps the copyright in the Article. Nothing in this agreement transfers the copyright to the Journal.'),
  ...cl2(3, 'The licence the Author gives the Journal', 'The Author gives the Journal a non-exclusive, worldwide, royalty-free licence, for the legal life of the copyright, to publish the Article; to store, archive and preserve it; to make it available to the public online; to make the copies and format changes needed to do so; to include it in indexing services and repositories; and to make it available to readers under the Creative Commons Attribution-NonCommercial 4.0 International licence (CC BY-NC 4.0, https://creativecommons.org/licenses/by-nc/4.0/). Because the licence is non-exclusive, the Author may also publish or share the Article elsewhere, as long as the Journal is credited as the place of first publication.'),
  ...cl2(4, 'Fees', 'The Journal states on its website an Article Processing Charge of USD 50 to 100 per accepted manuscript. The Author is told the amount that applies only after the Article has passed review and received an acceptance decision. Signing this agreement does not by itself create a payment obligation beyond what the Journal has told the Author in writing.'),
  ...cl2(5, 'Corrections and withdrawal', 'The Journal may correct, add a notice to, or retract the Article if there is a serious error or a breach of its publication ethics policy, following that policy. The Author agrees to help the Journal correct errors that the Author discovers.'),
  ...cl2(6, 'Personal data', 'The Journal uses the Author\'s details only for editorial and publication work, as described in its privacy statement. Published articles show the authors\' names and affiliations.'),
  ...cl2(7, 'Governing law', 'This agreement is governed by the law of [country or state, to be chosen by the Journal].'),
  head('Signature'),
  para('By signing, the corresponding author confirms that they have the authority to sign for all the authors of the Article.'),
  blank('Signature'), blank('Printed name'), blank('Date'),
];
const agreement = new Document({ creator: JOURNAL, title: 'Copyright and publication agreement', styles, sections: [{ properties: { page }, footers: footer('copyright and publication agreement'), children: ag }] });

// ---------------- certificate (A4 landscape) ----------------
const logo = fs.readFileSync(path.join(root, 'ojs/plugins/themes/worj/assets/img/logo-lockup.jpg'));
const ctr = (t, o = {}, after = 160) => new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after }, children: [run(t, o)] });
const certBorder = { top: { style: BorderStyle.DOUBLE, size: 18, color: '1F3A5F', space: 12 }, bottom: { style: BorderStyle.DOUBLE, size: 18, color: '1F3A5F', space: 12 }, left: { style: BorderStyle.DOUBLE, size: 18, color: '1F3A5F', space: 12 }, right: { style: BorderStyle.DOUBLE, size: 18, color: '1F3A5F', space: 12 } };
const none = { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' };
const nb = { top: none, bottom: none, left: none, right: none };
const sig = (label) => new TableCell({ width: { size: 4800, type: WidthType.DXA }, borders: nb, children: [new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 600 }, border: { top: { style: BorderStyle.SINGLE, size: 6, color: '000000', space: 4 } }, children: [run(label, { size: 22 })] })] });
const gapc = new TableCell({ width: { size: 3000, type: WidthType.DXA }, borders: nb, children: [new Paragraph({ children: [] })] });
const cert = new Document({ creator: JOURNAL, title: 'Research Award certificate', styles, sections: [{
  properties: { page: { size: { width: 11906, height: 16838, orientation: PageOrientation.LANDSCAPE }, margin: { top: 900, bottom: 900, left: 1200, right: 1200 }, borders: { pageBorders: { display: 'allPages', offsetFrom: 'page', ...Object.fromEntries(Object.entries(certBorder).map(([k, v]) => [`page${k[0].toUpperCase()}${k.slice(1)}`, { ...v, space: 24 }])) } } } },
  children: [
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 100 }, children: [new ImageRun({ type: 'jpg', data: logo, transformation: { width: 220, height: 80 } })] }),
    ctr('CERTIFICATE OF RECOGNITION', { bold: true, size: 44, color: '1F3A5F' }, 100),
    ctr(JOURNAL + ' Research Awards', { size: 28 }, 300),
    ctr('This certificate is presented to', { italics: true, size: 26 }, 120),
    ctr('[Recipient name]', { bold: true, size: 48 }, 160),
    ctr('in recognition of outstanding research as the recipient of the', { size: 26 }, 80),
    ctr('[Award category, for example Best Researcher]', { bold: true, size: 32 }, 160),
    ctr('for the article "[Title of the article]"', { italics: true, size: 26 }, 80),
    ctr('[Volume and period, for example Volume 1, 2027]', { size: 26 }, 300),
    new Table({ width: { size: 12600, type: WidthType.DXA }, columnWidths: [4800, 3000, 4800], borders: { top: none, bottom: none, left: none, right: none, insideHorizontal: none, insideVertical: none }, rows: [new TableRow({ children: [sig('Prof. Paul John, Editor-in-Chief'), gapc, sig('Date')] })] }),
  ] }] });

Promise.all([
  out('ojs/client-content/downloads', 'WORJ-Manuscript-Template.docx', manuscript),
  out('ojs/client-content/downloads', 'WORJ-Cover-Letter-Template.docx', cover),
  out('ojs/client-content/downloads', 'WORJ-Copyright-and-Publication-Agreement.docx', agreement),
  out('ojs/client-content/internal', 'WORJ-Award-Certificate-Template.docx', cert),
]);
