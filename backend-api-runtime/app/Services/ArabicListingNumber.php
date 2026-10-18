<?php

namespace App\Services;

/** Bounded Arabic cardinal numbers used only beside an explicit listing label. */
class ArabicListingNumber
{
    private const VALUES = [
        'واحد'=>1, 'واحده'=>1, 'احد'=>1, 'اثنان'=>2, 'اثنين'=>2, 'اثنتان'=>2, 'اثنتين'=>2,
        'ثلاث'=>3, 'ثلاثه'=>3, 'اربع'=>4, 'اربعه'=>4, 'خمس'=>5, 'خمسه'=>5,
        'ست'=>6, 'سته'=>6, 'سبع'=>7, 'سبعه'=>7, 'ثمان'=>8, 'ثماني'=>8, 'ثمانيه'=>8,
        'تسع'=>9, 'تسعه'=>9, 'عشر'=>10, 'عشره'=>10,
        'عشرون'=>20, 'عشرين'=>20, 'ثلاثون'=>30, 'ثلاثين'=>30, 'اربعون'=>40, 'اربعين'=>40,
        'خمسون'=>50, 'خمسين'=>50, 'ستون'=>60, 'ستين'=>60, 'سبعون'=>70, 'سبعين'=>70,
        'ثمانون'=>80, 'ثمانين'=>80, 'تسعون'=>90, 'تسعين'=>90,
        'مئه'=>100, 'مائه'=>100, 'ميه'=>100, 'مئتان'=>200, 'مئتين'=>200, 'مائتان'=>200, 'مائتين'=>200,
        'ثلاثمئه'=>300, 'ثلاثمائه'=>300, 'اربعمئه'=>400, 'اربعمائه'=>400,
        'خمسمئه'=>500, 'خمسمائه'=>500, 'ستمئه'=>600, 'ستمائه'=>600,
        'سبعمئه'=>700, 'سبعمائه'=>700, 'ثمانمئه'=>800, 'ثمانمائه'=>800,
        'تسعمئه'=>900, 'تسعمائه'=>900,
    ];
    private const SCALES = ['الف'=>1000, 'الاف'=>1000, 'الفين'=>2000, 'مليون'=>1000000, 'ملايين'=>1000000, 'مليونين'=>2000000];

    public static function normalize(string $text): string
    {
        $text = strtr($text, array_combine(preg_split('//u', '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', -1, PREG_SPLIT_NO_EMPTY), str_split('01234567890123456789')));
        $text = preg_replace('/[\x{0640}\x{064B}-\x{065F}\x{0670}]/u', '', $text);
        $text = strtr($text, ['أ'=>'ا', 'إ'=>'ا', 'آ'=>'ا', 'ٱ'=>'ا', 'ة'=>'ه', 'ى'=>'ي', '٫'=>'.', '٬'=>'']);
        return preg_replace('/(?<=\d),(?=\d{3}(?:\D|$))/u', '', $text);
    }

    public function pattern(): string
    {
        $words = array_keys(self::VALUES + self::SCALES);
        usort($words, fn ($a, $b) => mb_strlen($b) <=> mb_strlen($a));
        $token = '(?:\d+(?:\.\d+)?|'.implode('|', $words).')';
        return $token.'(?:\s+(?:و\s*)?'.$token.')*';
    }

    public function parse(string $text): ?float
    {
        $text = trim(self::normalize($text));
        $tokens = preg_split('/\s+(?:و\s*)?/u', $text);
        $total = 0.0; $part = 0.0; $previous = null; $lastScale = INF;
        foreach ($tokens as $token) {
            if (isset(self::SCALES[$token])) {
                $scale = self::SCALES[$token];
                if ($scale >= $lastScale) return null;
                $total += ($part ?: 1) * $scale; $part = 0; $previous = null; $lastScale = $scale;
                continue;
            }
            $value = self::VALUES[$token] ?? (is_numeric($token) ? (float) $token : null);
            if ($value === null || $value < 0) return null;
            if ($previous !== null) {
                // Adjacent alternatives/ungrammatical numeric fragments are not a sum.
                if ($value === 100 && $previous >= 3 && $previous <= 9 && $part == $previous) $part *= 100;
                elseif ($value === 10 && $previous >= 1 && $previous <= 9 && $part == $previous) $part += 10;
                elseif ($previous >= 100 && fmod($previous, 100) === 0.0 && $value < 100) $part += $value;
                elseif ($previous < 10 && $value >= 20 && $value <= 90 && fmod($value, 10) === 0.0) $part += $value;
                elseif ($previous >= 20 && $previous <= 90 && $value < 10) $part += $value;
                else return null;
            } else $part = $value;
            $previous = $value;
        }
        $result = $total + $part;
        return $result > 0 && $result <= 1000000000000 ? $result : null;
    }
}
