/* src/utils/svgUtils.js */
export function stripSvgLabels(svgMarkup) {
  if (!svgMarkup) return '';
  return svgMarkup
    .replace(/<text[\s\S]*?>[\s\S]*?<\/text>/gi, '')
    .replace(/<tspan[\s\S]*?>[\s\S]*?<\/tspan>/gi, '')
    .replace(/<desc[\s\S]*?>[\s\S]*?<\/desc>/gi, '')
    .replace(/<title[\s\S]*?>[\s\S]*?<\/title>/gi, '');
}
