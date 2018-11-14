#!/usr/bin/env python
from serial import Serial, EIGHTBITS, PARITY_NONE, STOPBITS_ONE
from sys import argv, stdout
import string

if len(argv) != 5:
    print("Usage: {} COM[number] [RSA_KEY_LENGTH] [key file name] [enc file name]")
    exit()
s = Serial(
    port=argv[1],
    baudrate=115200,
    bytesize=EIGHTBITS,
    parity=PARITY_NONE,
    stopbits=STOPBITS_ONE,
    xonxoff=False,
    rtscts=False
)
size = int(argv[2])
fp_key = open('{}'.format(argv[3]), 'rb')
fp_enc = open('{}'.format(argv[4]), 'rb')
fp_dec = open('dec.bin', 'wb')
assert fp_key and fp_enc and fp_dec
key = fp_key.read(size//4)
enc = fp_enc.read()
fixed = len(enc) % (size//8) == 0
if not fixed:
    enc += (size//8 - len(enc)%(size//8))*b'\x00'

assert len(enc) % (size//8) == 0
#b'10000110'
#s.write(b'00000110') # write header
if size == 512:
    header = 0x80
elif size == 256:
    header = 0x00
else:
    print("Invalid key size!")
    exit()
header += (len(enc)//(size//8)) -1
header = bytes([header])
s.write(header) # write header
s.write(key)

for i in range(0, len(enc), size//8):
    s.write(enc[i:i+size//8])
    dec = s.read(size//8-1)
    fp_dec.write(dec)

fp_key.close()
fp_enc.close()
fp_dec.close()
