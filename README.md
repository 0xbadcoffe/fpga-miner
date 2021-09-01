## Installing ModelSim

Go to the intelFpga 
[website](https://fpgasoftware.intel.com/20.1.1/?edition=lite&product=modelsim_ae&platform=windows#tabs-2).

Download ModelSim-Intel FPGA Edition (includes Starter Edition).

Install it.

## Creating project and running simulation

Start ModelSim and run the following commands:

    do C:/Alephium/Git/fpga-miner/create_project.do
    project compileall
    vsim work.HashGenTB
    do C:/Alephium/Git/fpga-miner/wave.do
    run -all
    
## Register map

| Address Space Offset | Register Name | Access Type | Defaul Value| Description |
| -------------------- | ------------- |------------ | ----------- | ----------- |
| 0x0000  | UPDATE_TRIGGER | R/W | 0x0 | |
| 0x0004  | GROUP_DIRECTIONS | R/W | 0x0 | |
| 0x0008  | GROUPS | R/W | 0x0 | |
| 0x000C  | CHUNK_LENGTH | R/W | 0x0 | Number of bytes in a chunk. |
| 0x0010  | TARGET_0 | R/W | 0x0 | Target difficulty |
| 0x0014  | TARGET_1 | R/W | 0x0 | |
| 0x0018  | TARGET_2 | R/W | 0x0 | |
| 0x001C  | TARGET_3 | R/W | 0x0 | |
| 0x0020  | TARGET_4 | R/W | 0x0 | |
| 0x0024  | TARGET_5 | R/W | 0x0 | |
| 0x0028  | TARGET_6 | R/W | 0x0 | |
| 0x002C  | TARGET_7 | R/W | 0x0 | |
| 0x0030  | NONCE_0 | R/W | 0x0 | Nonce of the chunk |
| 0x0034  | NONCE_1 | R/W | 0x0 | |
| 0x003C  | NONCE_2 | R/W | 0x0 | |
| 0x0040  | NONCE_3 | R/W | 0x0 | |
| 0x0044  | NONCE_4 | R/W | 0x0 | |
| 0x0048  | NONCE_5 | R/W | 0x0 | |

### UPDATE_TRIGGER register

| [31:1] | [0] |
| ---- | ---- |
| Reserved | Update |

| Bits | Name | Core Access | Reset Value | Description |
| ---- | ---- |---- | ---- | ---- |
| 31-1  | Reserved | N/A | 0 | Reserved. Set to zeros on a read. |
| 0  | Update | R/W | 0 | Writing 1 triggers a new mining process, toggle. |

### GROUP_DIRECTIONS register

| [31:24] | [23:16] | [15:8] | [7:0] |
| ---- | ---- | ---- | ---- |
| Reserved | From Group | Reserved | To Group |

| Bits | Name | Core Access | Reset Value | Description |
| ---- | ---- |---- | ---- | ---- |
| 31-24  | Reserved | N/A | 0 | Reserved. Set to zeros on a read. |
| 23-16  | From Group | R/W | 0 |  |
| 15-8  | Reserved | N/A | 0 | Reserved. Set to zeros on a read. |
| 7-0  | To Group | R/W | 0 |  |

### GROUPS register

| [31:24] | [23:16] | [15:8] | [7:0] |
| ---- | ---- | ---- | ---- |
| Reserved | Groups | Chain Number | Groups Shifter |

| Bits | Name | Core Access | Reset Value | Description |
| ---- | ---- |---- | ---- | ---- |
| 31-24  | Reserved | N/A | 0 | Reserved. Set to zeros on a read. |
| 23-16  | Groups | R/W | 0 |  |
| 15-8  | Chain Number | R/W | 0 | Groups*Groups |
| 7-0  | Groups Shifter | R/W | 0 | Division by the powers of two. |

### CHUNK_LENGTH register

| [31:11] | [10:0] | 
| ---- | ---- | 
| Reserved | Chunk Length | 

| Bits | Name | Core Access | Reset Value | Description |
| ---- | ---- |---- | ---- | ---- |
| 31-11  | Reserved | N/A | 0 | Reserved. Set to zeros on a read. |
| 10-0 | Chunk Length| R/W | 0 | Number of bytes in a chunk. Nonce + Headerblob|


### TARGET registers

The 8 Target registers contain the target difficulty of the mining. 
The valid hash needs to  be less than or equal to the Target.
The Target difficulty is 32 bytes, 256 bits.

* TARGET_0 -> Target[31:0]
* TARGET_1 -> Target[63:32]
* TARGET_2 -> Target[95:64]
* TARGET_3 -> Target[127:96]
* TARGET_4 -> Target[159:128]
* TARGET_5 -> Target[191:160]
* TARGET_6 -> Target[223:192]
* TARGET_7 -> Target[251:224]


### NONCE registers

The 6 Nonce registers contain the starting nonce value, 
which is added to the beginning of the headerblob & they are getting hashed together.
The miner increments the value of the nonce & hashes the chunk until the conditions get satisfied. 
The starting nonce is 24 bytes, 192 bits.

* NONCE_0 -> Nonce[31:0]
* NONCE_1 -> Nonce[63:32]
* NONCE_2 -> Nonce[95:64]
* NONCE_3 -> Nonce[127:96]
* NONCE_4 -> Nonce[159:128]
* NONCE_5 -> Nonce[191:160]


