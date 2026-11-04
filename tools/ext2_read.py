"""Read-only ext2 inspection; never mounts or modifies an image."""
import argparse, gzip, mmap, pathlib, struct

class Ext2:
    def __init__(self, path):
        self.file = open(path, 'rb')
        self.data = mmap.mmap(self.file.fileno(), 0, access=mmap.ACCESS_READ)
        if self.data[:4] == bytes.fromhex('27051956'):
            self.data = gzip.decompress(self.data[64:])
        if self.u16(1080) != 0xef53:
            raise ValueError('Not ext2')
        self.block = 1024 << self.u32(1048)
        self.ipg = self.u32(1064)
        self.inode_size = (self.u16(1112) if self.u32(1100) else 128) or 128
        self.gdt = (2 if self.block == 1024 else 1) * self.block

    def u16(self, offset): return struct.unpack_from('<H', self.data, offset)[0]
    def u32(self, offset): return struct.unpack_from('<I', self.data, offset)[0]
    def close(self):
        if hasattr(self.data,'close'): self.data.close()
        self.file.close()
    def inode(self, number):
        group, index = divmod(number - 1, self.ipg)
        table = self.u32(self.gdt + group * 32 + 8)
        return table * self.block + index * self.inode_size

    def indirect(self, block, depth):
        if not block:
            return
        for offset in range(block*self.block, (block+1)*self.block, 4):
            value = self.u32(offset)
            if depth == 1:
                yield value
            else:
                yield from self.indirect(value, depth-1)

    def content(self, number):
        inode = self.inode(number)
        size = self.u32(inode+4)
        mode = self.u16(inode)
        if mode & 0xf000 == 0xa000 and size <= 60:
            return bytes(self.data[inode+40:inode+40+size])
        blocks = [self.u32(inode+40+i*4) for i in range(12)]
        for depth in range(1,4):
            if len(blocks)*self.block >= size: break
            blocks.extend(self.indirect(self.u32(inode+40+(11+depth)*4), depth))
        chunks = []
        for block in blocks[:(size+self.block-1)//self.block]:
            chunks.append(bytes(self.data[block*self.block:(block+1)*self.block]) if block else bytes(self.block))
        return b''.join(chunks)[:size]

    def entries(self, number):
        content=self.content(number)
        offset=0
        result={}
        while offset+8 <= len(content):
            ino, length = struct.unpack_from('<IH',content,offset)
            if length < 8: raise ValueError('Invalid directory entry')
            name_len=content[offset+6]
            name=content[offset+8:offset+8+name_len].decode('utf-8','surrogateescape')
            if ino: result[name]=ino
            offset+=length
        return result

    def resolve(self, path):
        current=2
        for component in pathlib.PurePosixPath(path).parts:
            if component=='/': continue
            current=self.entries(current)[component]
        return current

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('image')
    parser.add_argument('path')
    parser.add_argument('--output')
    args=parser.parse_args()
    fs=Ext2(args.image)
    ino=fs.resolve(args.path)
    if fs.u16(fs.inode(ino)) & 0xf000 == 0x4000:
        print('\n'.join(fs.entries(ino)))
    else:
        data=fs.content(ino)
        if args.output:
            dest=pathlib.Path(args.output); dest.parent.mkdir(parents=True, exist_ok=True); dest.write_bytes(data)
        else:
            print(data.decode('utf-8','replace'))
