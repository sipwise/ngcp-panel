// Renders the OpenAPI document of /api?swagger=1 as a PDF (pdfmake, loaded on demand).
(function (window, document) {
    'use strict';

    const PDFMAKE_SCRIPTS = [
        '/static/js/libs/pdfmake/pdfmake.min.js',
        '/static/js/libs/pdfmake/vfs_fonts.js',
    ];
    const SPEC_URL = '/api?swagger=1';
    const FILENAME_PREFIX = 'ngcp-api-1-documentation-';
    const METHODS = ['get', 'post', 'put', 'patch', 'delete'];
    const METHOD_COLORS = {
        get: '#61affe', post: '#49cc90', put: '#fca130', patch: '#50e3c2', delete: '#f93e3e',
    };
    const COLOR = '#54893B';
    const SCHEMA_REF = '#/components/schemas/';
    const MAX_DEPTH = 6;

    function htmlToText(html) {
        if (html === undefined || html === null) return '';
        const doc = new DOMParser().parseFromString(String(html), 'text/html');
        return (doc.body.textContent || '').replace(/[ \t]+/g, ' ').trim();
    }

    function schemaAnchor(name) {
        return 'schema-' + name;
    }

    function resolve(spec, obj) {
        if (!obj || !obj.$ref || obj.$ref.indexOf('#/') !== 0) return obj;
        let node = spec;
        for (const key of obj.$ref.substring(2).split('/')) {
            node = node ? node[key] : undefined;
        }
        return node || obj;
    }

    function typeLabel(schema, models) {
        if (!schema) return '';
        if (schema.$ref) {
            if (schema.$ref.indexOf(SCHEMA_REF) === 0) {
                const name = schema.$ref.substring(SCHEMA_REF.length);
                return models[name]
                    ? { text: name, linkToDestination: schemaAnchor(name), style: 'link' }
                    : name;
            }
            return schema.$ref.replace(/#\/?$/, '');
        }
        if (schema.type === 'array') {
            return { text: ['array of ', typeLabel(schema.items, models)] };
        }
        let label = schema.type || '';
        if (schema.format) label += ' (' + schema.format + ')';
        return label;
    }

    function describe(schema) {
        const parts = [];
        const desc = htmlToText(schema.description);
        if (desc) parts.push(desc);
        const values = schema.enum || (schema.items && schema.items.enum);
        if (values && values.length) {
            parts.push({ text: '\nAllowed values: ', italics: true });
            parts.push({ text: values.map(String).join(', '), style: 'code' });
        }
        if (schema.example !== undefined) {
            parts.push({ text: '\nExample: ', italics: true });
            parts.push({ text: JSON.stringify(schema.example), style: 'code' });
        }
        return { text: parts };
    }

    function propertyRows(schema, prefix, rows, models, depth) {
        if (!schema || !schema.properties || depth > MAX_DEPTH) return rows;
        const required = schema.required || [];
        for (const name of Object.keys(schema.properties).sort()) {
            const prop = schema.properties[name] || {};
            const field = prefix + name;
            rows.push([
                { text: field, style: 'code', bold: required.indexOf(name) >= 0 },
                typeLabel(prop, models),
                required.indexOf(name) >= 0 ? 'yes' : '',
                describe(prop),
            ]);
            if (prop.properties) {
                propertyRows(prop, field + '.', rows, models, depth + 1);
            } else if (prop.type === 'array' && prop.items && prop.items.properties) {
                propertyRows(prop.items, field + '[].', rows, models, depth + 1);
            }
        }
        return rows;
    }

    function table(header, rows, widths) {
        return {
            table: {
                headerRows: 1,
                dontBreakRows: true,
                widths: widths,
                body: [header.map(h => ({ text: h, style: 'tableHeader' }))].concat(rows),
            },
            layout: 'lightHorizontalLines',
            style: 'table',
        };
    }

    function schemaContent(schema, models) {
        if (schema && schema.type === 'object' && schema.properties) {
            return table(['Field', 'Type', 'Required', 'Description'],
                propertyRows(schema, '', [], models, 0), [140, 90, 45, '*']);
        }
        return { text: ['Type: ', typeLabel(schema, models)], margin: [0, 0, 0, 6] };
    }

    function contentLabel(content, models) {
        const parts = [];
        for (const type of Object.keys(content || {})) {
            if (parts.length) parts.push('\n');
            parts.push({ text: type, style: 'code' });
            const schema = content[type].schema;
            if (schema) parts.push(': ', typeLabel(schema, models));
        }
        return { text: parts };
    }

    function operationBlock(spec, path, method, op, models) {
        const block = [{
            table: {
                widths: [50, '*'],
                body: [[
                    { text: method.toUpperCase(), bold: true, color: 'white',
                      fillColor: METHOD_COLORS[method], alignment: 'center' },
                    { text: path, style: 'path', fillColor: '#f2f2f2' },
                ]],
            },
            layout: 'noBorders',
            margin: [0, 10, 0, 4],
        }];
        if (op.summary) block.push({ text: htmlToText(op.summary), margin: [0, 0, 0, 4] });
        if (op.description) block.push({ text: htmlToText(op.description), margin: [0, 0, 0, 4] });

        const params = (op.parameters || []).map(p => resolve(spec, p));
        if (params.length) {
            block.push({ text: 'Parameters', style: 'h4' });
            block.push(table(['Name', 'In', 'Type', 'Required', 'Description'],
                params.map(p => [
                    { text: p.name, style: 'code', bold: !!p.required },
                    p.in || '',
                    typeLabel(p.schema, models),
                    p.required ? 'yes' : '',
                    describe(Object.assign({}, p.schema, {
                        description: p.description,
                        example: p.example !== undefined ? p.example : (p.schema || {}).example,
                    })),
                ]), [110, 35, 70, 45, '*']));
        }

        const body = resolve(spec, op.requestBody);
        if (body) {
            block.push({ text: 'Request body', style: 'h4' });
            const desc = htmlToText(body.description);
            if (desc) block.push({ text: desc, margin: [0, 0, 0, 2] });
            block.push({ text: [contentLabel(body.content, models),
                body.required ? { text: ' (required)', italics: true } : ''], margin: [0, 0, 0, 4] });
        }

        const responses = op.responses || {};
        const codes = Object.keys(responses).sort();
        if (codes.length) {
            block.push({ text: 'Responses', style: 'h4' });
            block.push(table(['Code', 'Description', 'Content'],
                codes.map(code => {
                    const r = resolve(spec, responses[code]) || {};
                    return [
                        { text: code, bold: true },
                        htmlToText(r.description),
                        contentLabel(r.content, models),
                    ];
                }), [45, '*', '*']));
        }
        return { stack: block };
    }

    const HEADING_STYLES = { H2: 'h1', H3: 'h2', H4: 'h3', H5: 'h4', H6: 'h4' };
    const BLOCK_TAGS = ['P', 'DIV', 'NAV', 'UL', 'OL', 'CODE', 'PRE', 'TABLE',
                        'H1', 'H2', 'H3', 'H4', 'H5', 'H6'];

    function htmlAnchor(id) {
        return 'html-' + id;
    }

    function codeText(el) {
        const lines = el.textContent.replace(/\t/g, '    ').split('\n');
        while (lines.length && !lines[0].trim()) lines.shift();
        while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
        if (!lines.length) return '';
        const indent = Math.min(...lines.filter(l => l.trim()).map(l => l.match(/^ */)[0].length));
        return lines.map(l => l.substring(indent)).join('\n');
    }

    function htmlInline(node, style, anchors, out) {
        if (node.nodeType === 3) {
            out.push(Object.assign({ text: node.textContent.replace(/\s+/g, ' ') }, style));
            return out;
        }
        if (node.nodeType !== 1) return out;
        if (node.tagName === 'BR') {
            out.push({ text: '\n' });
            return out;
        }
        const s = Object.assign({}, style);
        if (node.tagName === 'B' || node.tagName === 'STRONG') s.bold = true;
        if (node.tagName === 'I' || node.tagName === 'EM') s.italics = true;
        if (node.tagName === 'SPAN') s.style = 'code';
        if (node.tagName === 'A') {
            const href = node.getAttribute('href') || '';
            if (href.charAt(0) === '#') {
                if (anchors.has(href.substring(1))) {
                    s.linkToDestination = htmlAnchor(href.substring(1));
                    s.style = 'link';
                }
            } else if (href) {
                s.link = node.href;
                s.style = 'link';
            }
        }
        for (const child of node.childNodes) htmlInline(child, s, anchors, out);
        return out;
    }

    function htmlBlock(el, anchors, out) {
        const tag = el.tagName;
        if (HEADING_STYLES[tag]) {
            const heading = { text: el.textContent.replace(/\s+/g, ' ').trim(), style: HEADING_STYLES[tag] };
            if (el.id) heading.id = htmlAnchor(el.id);
            if (tag === 'H2') {
                heading.tocItem = true;
                heading.pageBreak = 'before';
            } else if (tag === 'H3') {
                heading.tocItem = true;
                heading.tocMargin = [15, 0, 0, 0];
            }
            out.push(heading);
        } else if (tag === 'CODE' || tag === 'PRE') {
            out.push({
                table: { widths: ['*'], body: [[{ text: codeText(el), style: 'codeBlock',
                                                  preserveLeadingSpaces: true, fillColor: '#f5f5f5' }]] },
                layout: 'noBorders',
                margin: [0, 2, 0, 8],
            });
        } else if (tag === 'UL' || tag === 'OL') {
            const items = Array.from(el.children).filter(li => li.tagName === 'LI')
                .map(li => ({ stack: htmlBlocks(li, anchors, []) }));
            out.push({ [tag.toLowerCase()]: items, margin: [0, 0, 0, 6] });
        } else {
            htmlBlocks(el, anchors, out);
        }
        return out;
    }

    function htmlBlocks(node, anchors, out) {
        let inline = [];
        const flush = () => {
            if (inline.some(i => i.text.trim())) {
                inline[0].text = inline[0].text.replace(/^\s+/, '');
                inline[inline.length - 1].text = inline[inline.length - 1].text.replace(/\s+$/, '');
                out.push({ text: inline, margin: [0, 0, 0, 6] });
            }
            inline = [];
        };
        for (const child of node.childNodes) {
            if (child.nodeType === 1 && BLOCK_TAGS.indexOf(child.tagName) >= 0) {
                flush();
                htmlBlock(child, anchors, out);
            } else {
                htmlInline(child, {}, anchors, inline);
            }
        }
        flush();
        return out;
    }

    // the intro chapters (Introduction, Authentication, ...) rendered on the page
    function pageChapters(doc) {
        const chapters = Array.from(doc.querySelectorAll('.chapter.sipwclass'))
            .filter(chapter => chapter.querySelector('h2[id]'));
        const anchors = new Set();
        for (const chapter of chapters) {
            for (const heading of chapter.querySelectorAll('h2[id], h3[id], h4[id], h5[id], h6[id]')) {
                anchors.add(heading.id);
            }
        }
        const out = [];
        for (const chapter of chapters) htmlBlocks(chapter, anchors, out);
        return out;
    }

    function timestamp(date) {
        const pad = n => String(n).padStart(2, '0');
        return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' '
            + pad(date.getHours()) + ':' + pad(date.getMinutes()) + ':' + pad(date.getSeconds());
    }

    function buildDocDefinition(spec, chapters, generated) {
        const info = spec.info || {};
        const description = htmlToText(info.description).replace(/\s*\(role [^)]*\)/, '');
        const models = (spec.components && spec.components.schemas) || {};
        const tags = (spec.tags || []).slice();
        const tagDescriptions = {};
        for (const tag of tags) tagDescriptions[tag.name] = tag.description;

        const operations = {};
        for (const path of Object.keys(spec.paths || {}).sort()) {
            const item = spec.paths[path];
            for (const method of METHODS) {
                const op = item[method];
                if (!op) continue;
                const tag = (op.tags && op.tags[0]) || 'default';
                if (!(tag in tagDescriptions)) {
                    tagDescriptions[tag] = undefined;
                    tags.push({ name: tag });
                }
                (operations[tag] = operations[tag] || []).push({ path: path, method: method, op: op });
            }
        }
        tags.sort((a, b) => a.name.localeCompare(b.name));

        const content = [
            { text: info.title || 'API', style: 'title', margin: [0, 200, 0, 10] },
            { text: description, style: 'subtitle' },
            { text: 'Version ' + (info.version || ''), style: 'subtitle' },
            { text: timestamp(generated || new Date()), style: 'subtitle', margin: [0, 30, 0, 0] },
        ].concat(chapters || [], [
            { toc: { title: { text: 'Table of Contents', style: 'h1' } }, pageBreak: 'before' },
            { text: 'Resources', style: 'h1', tocItem: true, pageBreak: 'before' },
        ]);

        tags.forEach((tag, i) => {
            const ops = operations[tag.name] || [];
            if (!ops.length) return;
            content.push({ text: tag.name, style: 'h2', tocItem: true, tocMargin: [15, 0, 0, 0],
                           pageBreak: i ? 'before' : undefined });
            const desc = htmlToText(tag.description);
            if (desc) content.push({ text: desc, margin: [0, 0, 0, 4] });
            if (models[tag.name]) {
                content.push({ text: ['Model: ', typeLabel({ $ref: SCHEMA_REF + tag.name }, models)],
                               margin: [0, 0, 0, 4] });
            }
            for (const o of ops) content.push(operationBlock(spec, o.path, o.method, o.op, models));
        });

        content.push({ text: 'Models', style: 'h1', tocItem: true, pageBreak: 'before' });
        Object.keys(models).sort().forEach((name, i) => {
            content.push({ text: name, style: 'h2', id: schemaAnchor(name), tocItem: true,
                           tocMargin: [15, 0, 0, 0], margin: [0, i ? 16 : 0, 0, 6] });
            const desc = htmlToText(models[name].description);
            if (desc) content.push({ text: desc, margin: [0, 0, 0, 4] });
            content.push(schemaContent(models[name], models));
        });

        return {
            info: { title: info.title, subject: description, creator: 'Sipwise NGCP' },
            pageSize: 'A4',
            pageMargins: [40, 50, 40, 50],
            header: (page) => page > 1
                ? { text: (info.title || 'API') + ' ' + (info.version || ''), style: 'pageHeader' }
                : null,
            footer: (page, pages) => page > 1
                ? { text: page + ' / ' + pages, style: 'pageFooter' }
                : null,
            content: content,
            defaultStyle: { fontSize: 9, lineHeight: 1.15 },
            styles: {
                title: { fontSize: 28, bold: true, color: COLOR, alignment: 'center' },
                subtitle: { fontSize: 12, alignment: 'center', margin: [0, 4, 0, 0] },
                h1: { fontSize: 20, bold: true, color: COLOR, margin: [0, 0, 0, 12] },
                h2: { fontSize: 15, bold: true, color: COLOR, margin: [0, 0, 0, 6] },
                h3: { fontSize: 12, bold: true, margin: [0, 8, 0, 4] },
                h4: { fontSize: 10, bold: true, margin: [0, 6, 0, 3] },
                path: { bold: true, color: '#333' },
                code: { color: '#7a3e00' },
                codeBlock: { fontSize: 8, color: '#333', margin: [6, 4, 6, 4] },
                link: { color: COLOR, decoration: 'underline' },
                table: { margin: [0, 0, 0, 6], fontSize: 8 },
                tableHeader: { bold: true, fillColor: '#eeeeee' },
                pageHeader: { fontSize: 8, color: '#888', margin: [40, 25, 40, 0] },
                pageFooter: { fontSize: 8, color: '#888', alignment: 'right', margin: [40, 15, 40, 0] },
            },
        };
    }

    function loadScript(src) {
        return new Promise((resolveLoad, rejectLoad) => {
            const script = document.createElement('script');
            script.src = src;
            script.onload = resolveLoad;
            script.onerror = () => rejectLoad(new Error('Failed to load ' + src));
            document.head.appendChild(script);
        });
    }

    function loadPdfmake() {
        if (window.pdfMake) return Promise.resolve(window.pdfMake);
        return PDFMAKE_SCRIPTS.reduce((p, src) => p.then(() => loadScript(src)), Promise.resolve())
            .then(() => window.pdfMake);
    }

    function download(button) {
        const label = button.textContent;
        button.disabled = true;
        button.textContent = 'Generating PDF...';
        return Promise.all([
            fetch(SPEC_URL, { credentials: 'same-origin', headers: { Accept: 'application/json' } })
                .then(res => {
                    if (!res.ok) throw new Error('Failed to fetch ' + SPEC_URL + ': ' + res.status);
                    return res.json();
                }),
            loadPdfmake(),
        ]).then(([spec, pdfMake]) => {
            const now = new Date();
            return pdfMake.createPdf(buildDocDefinition(spec, pageChapters(document), now))
                .download(FILENAME_PREFIX + timestamp(now).replace(/\D/g, '') + '.pdf');
        }).catch(err => {
            window.alert('Could not generate the PDF: ' + err.message);
        }).then(() => {
            button.disabled = false;
            button.textContent = label;
        });
    }

    window.NGCPApiDocPdf = { buildDocDefinition: buildDocDefinition, pageChapters: pageChapters, download: download };

    document.addEventListener('DOMContentLoaded', () => {
        const button = document.getElementById('apidoc-pdf-download');
        if (button) button.addEventListener('click', () => download(button));
    });
})(window, document);
