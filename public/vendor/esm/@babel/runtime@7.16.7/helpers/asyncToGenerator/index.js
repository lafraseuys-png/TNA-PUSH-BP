/**
 * Bundled by jsDelivr using Rollup v4.62.2 and esbuild v0.28.1.
 * Original file: /npm/@babel/runtime@7.16.7/helpers/esm/asyncToGenerator.js
 *
 * Do NOT use SRI with dynamically generated files! More information: https://www.jsdelivr.com/using-sri-with-dynamic-files
 */
function c(u,i,s,t,o,a,r){try{var e=u[a](r),n=e.value}catch(f){s(f);return}e.done?i(n):Promise.resolve(n).then(t,o)}function h(u){return function(){var i=this,s=arguments;return new Promise(function(t,o){var a=u.apply(i,s);function r(n){c(a,t,o,r,e,"next",n)}function e(n){c(a,t,o,r,e,"throw",n)}r(void 0)})}}export{h as default};
