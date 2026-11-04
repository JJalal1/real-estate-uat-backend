// Existing workspace authoring runtime only; no mobile dependency or service.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const sharp = require(path.join(process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES, 'sharp'));
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const brand = path.join(root, 'mobile_app/assets/brand');
const mark = await fs.readFile(path.join(brand, 'aqer-mark.svg'));
const word = await fs.readFile(path.join(brand, 'aqer-wordmark.svg'));
for (const [density, size] of [['mdpi',48],['hdpi',72],['xhdpi',96],['xxhdpi',144],['xxxhdpi',192]]) {
  const base = path.join(root, 'mobile_app/android/app/src/main/res');
  await sharp(mark).resize(size,size).png().toFile(path.join(base, `mipmap-${density}/ic_launcher.png`));
  const folder = path.join(base, `drawable-${density}`);
  await fs.mkdir(folder, {recursive:true});
  const factor = size / 48;
  await sharp(word).resize(Math.round(220*factor),Math.round(82*factor), {fit:'contain',background:'#FFFFFF'}).png()
    .toFile(path.join(folder,'aqer_launch_wordmark.png'));
}
const ios = path.join(root,'mobile_app/ios/Runner/Assets.xcassets/AppIcon.appiconset');
const entries = JSON.parse(await fs.readFile(path.join(ios,'Contents.json'))).images;
const seen = new Set();
for (const e of entries) {
  if (!e.filename || seen.has(e.filename)) continue;
  seen.add(e.filename);
  const size = Math.round(Number(e.size.split('x')[0]) * Number(e.scale.replace('x','')));
  await sharp(mark).resize(size,size).flatten({background:'#015a60'}).removeAlpha().png().toFile(path.join(ios,e.filename));
}
const launch = path.join(root,'mobile_app/ios/Runner/Assets.xcassets/LaunchImage.imageset');
for (const [file, size] of [['LaunchImage.png',220],['LaunchImage@2x.png',440],['LaunchImage@3x.png',660]]) {
  await sharp(word).resize({width:size}).png().toFile(path.join(launch,file));
}
const review = path.join(root,'../review/brand-integrated');
await fs.mkdir(review,{recursive:true});
for (const size of [48,192,512]) await sharp(mark).resize(size,size).png().toFile(path.join(review,`mark-${size}.png`));
await sharp(word).resize({width:1104}).png().toFile(path.join(review,'wordmark.png'));
console.log('Canonical SVG exported to existing Android/iOS icon slots and density-aware launch bitmaps.');
