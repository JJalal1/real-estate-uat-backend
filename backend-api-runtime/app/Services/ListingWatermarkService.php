<?php
namespace App\Services;

use RuntimeException;

/** Local GD only. Disabled until an owner-approved, fingerprint-pinned vector geometry exists. */
class ListingWatermarkService
{
    /** @var array<string,array<string,mixed>> */
    private static array $geometryCache = [];
    private ?array $geometry=null;
    public function version(): string
    {
        if (!config('listing_media.watermark.enabled')) return 'v1';
        $this->geometry();
        return 'v2-wm-'.substr(config('listing_media.watermark.approved_sha256'),0,20);
    }
    private function geometry(): array
    {
        if ($this->geometry!==null) return $this->geometry;
        $path=resource_path('brand/aqer-approved.json');
        $expected=(string)config('listing_media.watermark.approved_sha256');
        $cacheKey=$path.'|'.$expected;
        if (isset(self::$geometryCache[$cacheKey])) return $this->geometry=self::$geometryCache[$cacheKey];
        $bytes=is_file($path)?file_get_contents($path):false;
        if (!is_string($bytes) || !preg_match('/^[a-f0-9]{64}$/D',$expected) || !hash_equals($expected,hash('sha256',$bytes))) {
            throw new RuntimeException('Approved watermark geometry unavailable.');
        }
        $data=json_decode($bytes,true,32,JSON_THROW_ON_ERROR);
        if (($data['approval']??null)!=='owner-approved' || !is_array($data['layers']??null) || count($data['layers'])<1 || count($data['layers'])>20) throw new RuntimeException('Invalid approved watermark geometry.');
        $points=0;
        foreach($data['layers'] as $layer) foreach(['polygons','holes'] as $group) foreach($layer[$group]??[] as $polygon) {
            if(!is_array($polygon) || count($polygon)<3) throw new RuntimeException('Invalid watermark polygon.');
            foreach($polygon as $point) {
                if(!is_array($point) || count($point)!==2 || !is_numeric($point[0]) || !is_numeric($point[1]) || min($point)<0 || max($point)>1 || !is_finite((float)$point[0]) || !is_finite((float)$point[1])) throw new RuntimeException('Invalid watermark coordinate.');
                if(++$points>20000) throw new RuntimeException('Watermark geometry too large.');
            }
        }
        if ($points<3) throw new RuntimeException('Empty watermark geometry.');
        self::$geometryCache[$cacheKey]=$data;
        return $this->geometry=$data;
    }
    public function apply(\GdImage $output): void
    {
        if (!config('listing_media.watermark.enabled')) return;
        $geometry=$this->geometry(); $width=imagesx($output);$height=imagesy($output);
        $edge=max(24,(int)round(min($width,$height)*0.22));
        $tile=$this->stamp($geometry,$edge,0.10);
        try {
            $rotated=imagerotate($tile,28,imagecolorallocatealpha($tile,0,0,0,127));
            if(!$rotated) throw new RuntimeException('Watermark rotation failed.');
            try {
                imagesavealpha($rotated,true);imagealphablending($output,true);
                $step=max(1,(int)round($edge*2.2));
                for($y=-$edge;$y<$height;$y+=$step) for($x=-$edge;$x<$width;$x+=$step) imagecopy($output,$rotated,$x,$y,0,0,imagesx($rotated),imagesy($rotated));
            } finally { imagedestroy($rotated); }
        } finally { imagedestroy($tile); }
        $corner=$this->stamp($geometry,$edge,0.24);
        try { $margin=max(2,(int)round(min($width,$height)*0.025));imagecopy($output,$corner,max(0,$width-$edge-$margin),max(0,$height-$edge-$margin),0,0,$edge,$edge); }
        finally { imagedestroy($corner); }
    }
    private function stamp(array $geometry,int $edge,float $opacity): \GdImage
    {
        $image=imagecreatetruecolor($edge,$edge);imagealphablending($image,false);imagesavealpha($image,true);
        $clear=imagecolorallocatealpha($image,0,0,0,127);imagefill($image,0,0,$clear);
        $white=imagecolorallocatealpha($image,255,255,255,(int)round(127*(1-$opacity)));
        foreach($geometry['layers'] as $layer) foreach(['polygons'=>$white,'holes'=>$clear] as $group=>$color) foreach($layer[$group]??[] as $polygon) {
            $points=[];foreach($polygon as [$x,$y]) { $points[]=(int)round($x*($edge-1));$points[]=(int)round($y*($edge-1)); }
            imagefilledpolygon($image,$points,$color);
        }
        return $image;
    }
}
