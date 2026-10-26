<?php

namespace App\Services;

use Symfony\Component\HttpKernel\Exception\HttpException;

/** One GD encoder per runtime instance; cached derivatives never enter here. */
class ListingImageEncodingGate
{
    public function run(callable $encode): mixed
    {
        // Keep the inode: unlinking a released lock permits two independent
        // locks on different inodes. Kernel locks are released on process exit.
        $path=storage_path('framework/cache/listing-image-encoding.lock');
        $file=@fopen($path,'c');
        // CLI preparation may create a root-owned readable inode. flock on
        // Linux local storage does not need to write the file's contents.
        // Reuse that same inode; never unlink it or bypass the lock.
        if ($file===false) $file=@fopen($path,'r');
        if ($file===false) throw $this->busy();
        try {
            if (! flock($file,LOCK_EX|LOCK_NB)) throw $this->busy();
            try { return $encode(); }
            finally { flock($file,LOCK_UN); }
        } finally { fclose($file); }
    }

    private function busy(): HttpException
    {
        return new HttpException(503,'معالجة الصور مشغولة مؤقتًا. أعد محاولة الصورة بعد قليل.',null,['Retry-After'=>'2']);
    }
}
