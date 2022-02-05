#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "objio.h"

namespace x86
{
    typedef unsigned char byte;
    typedef unsigned int  uint32;

    enum decode_class_t
    {
        dcUNSUP,
        dcOAD,
        dcORM,
        dcMOVNX,
        dcSETCC,
        dcOMD,
        dcBOUND,
        dcBT,
        dcOD,
        dcENTER,
        dcOM,
        dcORMD,
        dcO,
        dcMOV,
        dcIO,
        dcSHIFT,
        dcOAO,
        dcGRP5,
        dcGRP3,
        dcOPOVR,
        dcADROVR,
        dcFPU,
        dcSTRING,
        dcDDB,
        dcELEMENTS
    };

    enum memory_access_t
    {
        maNone,
        maByte,
        maWord,
        maDWord,
        maReal4,
        maReal8,
        maReal10
    };

    enum mnemonic_t
    {
#define M(e, s) e,
#include "x86mne.h"
#undef M
        m_n_mnemonic_t
    };

    enum seg_regs_t
    {
        srES, srCS, srSS, srDS, srFS, srGS
    };

    struct decode_info_t
    {
        mnemonic_t mne;
        decode_class_t cls;
        memory_access_t MA;
        bool D; /* direction bit */
        bool W; /* word bit */
        bool S; /* sign extended */
    };

    static const char *mne_table[m_n_mnemonic_t] =
    {
#define M(e, s) s,
#include "x86mne.h"
#undef M
    };

    static const unsigned char *reg_names[3][8] =
    {
        { (unsigned char *)"al", (unsigned char *)"cl", (unsigned char *)"dl", (unsigned char *)"bl",
          (unsigned char *)"ah", (unsigned char *)"ch", (unsigned char *)"dh", (unsigned char *)"bh" },
        { (unsigned char *)"ax", (unsigned char *)"cx", (unsigned char *)"dx", (unsigned char *)"bx",
          (unsigned char *)"sp", (unsigned char *)"bp", (unsigned char *)"si", (unsigned char *)"di" },
        { (unsigned char *)"eax", (unsigned char *)"ecx", (unsigned char *)"edx", (unsigned char *)"ebx",
          (unsigned char *)"esp", (unsigned char *)"ebp", (unsigned char *)"esi", (unsigned char *)"edi" }
    };

    static const unsigned char *seg_reg_names[] =
    {
        (unsigned char *)"es", (unsigned char *)"cs", (unsigned char *)"ss",
        (unsigned char *)"ds", (unsigned char *)"fs", (unsigned char *)"gs"
    };

#define DECODE_OAD(index, mne, w)            { mne,    dcOAD,   maNone,                 false,    (w), false },
#define DECODE_ORM(index, mne, w, d)         { mne,    dcORM,   (w) ? maDWord : maByte, (d),      (w), false },
#define DECODE_MOVNX(index, mne, w, ma)      { mne,    dcMOVNX, (ma),                    false,   (w), false },
#define DECODE_SETCC(index, mne)             { mne,    dcSETCC, maNone,                  false, false, false },
#define DECODE_OMD(index, mne, w, s)         { mne,    dcOMD,   (w) ? maDWord : maByte,  false,   (w),   (s) },
#define DECODE_OD(index, mne, s)             { mne,    dcOD,    maNone,                  false, false,   (s) },
#define DECODE_OM(index, mne, w)             { mne,    dcOM,    (w) ? maDWord : maByte,  false,   (w), false },
#define DECODE_GRP3(index, mne, w)           { mne,    dcGRP3,  (w) ? maDWord : maByte,  false,   (w), false },
#define DECODE_ORMD(index, mne, s)           { mne,    dcORMD,  maDWord,                 false, false,   (s) },
#define DECODE_IO(index, mne, w)             { mne,    dcIO,    maNone,                  false,   (w), false },
#define DECODE_SHIFT(index, mne, w)          { mne,    dcSHIFT, (w) ? maDWord : maByte,  false,   (w), false },
#define DECODE_OAO(index, mne, w)            { mne,    dcOAO,   (w) ? maDWord : maByte,  false,   (w), false },
#define DECODE_STR(index, mne, w)            { mne,    dcSTRING,(w) ? maDWord : maByte,  false,   (w), false },
#define DECODE_MOV(index, w)                 { mMOV,   dcMOV,   maNone,                  false,   (w), false },
#define DECODE_O(index, mne)                 { mne,    dcO,     maNone,                  false, false, false },
#define DECODE_GRP5(index)                   { mUNSUP, dcGRP5,  maNone,                  false, false, false },
#define DECODE_ENTER(index, mne)             { mne,    dcENTER, maNone,                  false, false, false },
#define DECODE_BT(index, mne)                { mne,    dcBT,    maNone,                  false, false, false },
#define DECODE_FPU(index, mne)               { mne,    dcFPU,   maNone,                  false, false, false },
#define DECODE_UNSUPPORTED(index, mne, dc)   { mne,    (dc),    maNone,                  false, false, false },

    static const decode_info_t SBDT[] =
    {
#include "x86sbopc.h"
    };

/* index range: 0x80..0xbf; DBDT[0] = 0x80, DBDT[LEN(DBDT) - 1] = 0xbf */
    static const decode_info_t DBDT[] =
    {
#include "x86dbopc.h"
    };


    typedef unsigned int instruction_flags_t;

    const unsigned int if_none             = 0;
    const unsigned int if_dual_byte        = 1 <<  0; /* dual byte instruction */
    const unsigned int if_operand_override = 1 <<  1; /* operand override supplied */
    const unsigned int if_address_override = 1 <<  2; /* address override supplied */
    const unsigned int if_word             = 1 <<  3; /* word bit set */
    const unsigned int if_direction        = 1 <<  4; /* direction bit set */
    const unsigned int if_sign_extend      = 1 <<  5; /* sign extend bit set */
    const unsigned int if_data             = 1 <<  6; /* instruction has data */
    const unsigned int if_disp             = 1 <<  7; /* instruction has a displacement */
    const unsigned int if_label            = 1 <<  8; /* label should be output for this instruction */
    const unsigned int if_fixed            = 1 <<  9; /* memory access is fixed up */
    const unsigned int if_scaled           = 1 << 10; /* SIB byte */


    enum operand_class_t
    {
        oc_none,
        oc_enter,
        oc_reg,
        oc_orm
    };

    struct instruction_t
    {
        int pc; /* pc where this instruction starts */
        byte B0, B1; /* instruction bytes */
        mnemonic_t mne;
        instruction_flags_t flags;
        int data, disp;
        operand_class_t opcl;
        int mr, reg, rm;
        int ss, index, base;
        memory_access_t memacc;
        objio::fixup_kind_t fixkind;
        int offs; /* offset from pc of the instruction where fixup is located */
    };

    static int pc; // FIXME: needed?
    static byte *code_base;
    static decode_class_t kind;
    const decode_info_t *curr_decode;
    static instruction_t inst;
    static FILE *fp;

    static inline void pc_init(unsigned char *code, int p)
    {
        code_base = code;
        pc = p;
    }

    static inline void pc_set(instruction_t &i)
    {
        i.pc = pc;
    }

    static void default_inst(instruction_t &inst)
    {
        pc_set(inst);
        inst.B0 = '\0'; inst.B1 = '\0';
        inst.mne = mUNSUP;
        inst.flags = if_none;
        inst.data = 0; inst.disp = 0;
        inst.opcl = oc_none;
        inst.mr = 0; inst.reg = 0; inst.rm = 0;
        inst.ss = 0; inst.index = 0; inst.base = 0;
        inst.memacc = maNone;
        inst.fixkind = objio::fk_none;
        inst.offs = 0;
    }

    static inline byte get_byte(int at)
    {
        return code_base[at];
    }

    static inline  byte next_byte(void)
    {
        return code_base[pc++];
    }

    static inline int get_int_8(void)
    {
        int r = *(signed char *)&code_base[pc];
        assert(sizeof(signed char) == 1);
        pc += sizeof(byte);
        return r;
    }

    static inline int get_int_16(void)
    {
        int r = *(short *)&code_base[pc];
        pc += sizeof(short);
        return r;
    }

    static inline int get_int_32(void)
    {
        int r = *(int *)&code_base[pc];
        pc += sizeof(int);
        return r;
    }

    static void get_displ(int bits, int &disp, instruction_flags_t &flags, objio::fixup_kind_t &fk)
    {
        fk = objio::code_fixup(pc);
        inst.offs = pc - inst.pc;
        
        switch (bits)
        {
        case  8: disp = get_int_8(); flags |= if_disp; break;
        case 16: disp = get_int_16(); flags |= if_disp; break;
        case 32: disp = get_int_32(); flags |= if_disp; break;
        default: assert(false);
        }
    }
    
    static void get_immed(void)
    {
        inst.flags |= if_data;
        if (inst.flags & if_operand_override)
        {            
            if ((if_word & inst.flags) &&  !(if_sign_extend & inst.flags))
                inst.data = get_int_16();
            else
                inst.data = get_int_8();
        }
        else
        {
            if ((inst.flags & if_word) && !(if_sign_extend & inst.flags))
                inst.data = get_int_32();
            else
                inst.data = get_int_8();
        }
    }
        
    static void decode_mod_reg_rm(unsigned char mr, int &m, int &reg, int &rm)
    {
        m = (mr >> 6) & 3;
        reg = (mr >> 3) & 7;
        rm = mr & 7;
    }

    static void decode_sib(unsigned char b, int &ss, int &index, int &base)
    {
        ss = (b >> 6) & 3;
        index = (b >> 3) & 7;
        base = b & 7;
    }

    static bool has_sib(int mr, int rm)
    {
        return (mr !=3 ) && (rm == 4);
    }

    static void get_mem_ref(int mr, int rm, int &ss, int &index, int &base, int &disp, instruction_flags_t &flags)
    {
        if (has_sib(mr, rm))
        {
            decode_sib(next_byte(), ss, index, base);
            flags |= if_scaled;
            
            if ((mr == 0) && (base == 5))
                get_displ(32, disp, flags, inst.fixkind);
            else if (mr == 1)
                get_displ(8, disp, flags, inst.fixkind);
            else if (mr == 2)
                get_displ(32, disp, flags, inst.fixkind);
        }
        else
        {
            if ((mr == 0) && (rm == 5))
            {
                if (if_operand_override & flags)
                    get_displ(16, disp, flags, inst.fixkind);
                else
                    get_displ(32, disp, flags, inst.fixkind);
            }
            else if (mr == 1)
            {
                get_displ(8, disp, flags, inst.fixkind);
            }
            else if (mr == 2)
            {
                if (if_operand_override & flags)
                    get_displ(16, disp, flags, inst.fixkind);
                else
                    get_displ(32, disp, flags, inst.fixkind);
            }
        }
    }

    static void get_mod_reg_rm(void)
    {
        decode_mod_reg_rm(next_byte(), inst.mr, inst.reg, inst.rm);
        get_mem_ref(inst.mr, inst.rm, inst.ss, inst.index, inst.base, inst.disp, inst.flags);
    }

    static void put_pc(instruction_t &i, int &len)
    {
        fprintf(fp, "%4.4X: ",i.pc);
        len += 6;
    }

    static void put_bytes(instruction_t &i, int &len)
    {
        int j;
        for (j = i.pc; j < pc; ++j)
        {
            fprintf(fp, "%2.2X", get_byte(j));
            len += 2;
        }
    }

    static void put_pad(int len)
    {
        while (len-- > 0)
            fprintf(fp, " ");
    }

    static void put_dec(int i)
    {
        fprintf(fp, "%d", i);
    }

    static void put_hex(int i)
    {
        if (i < 0)
            fprintf(fp, "-0%XH", -i);
        else
            fprintf(fp, "0%XH", i);
    }

    static void put_num(int i)
    {
        if (-10 < i && i < 10)
            put_dec(i);
        else
            put_hex(i);
    }
    
    static void put_string(const unsigned char *s)
    {
        fprintf(fp, "%s", s);
    }

    static void put_string(const char *s)
    {
        fprintf(fp, "%s", s);
    }

    static void put_label(instruction_t &i, int &len)
    {
        assert(false);
    }

    static void put_reg(int reg, instruction_flags_t flags)
    {
        int i;

        assert((reg & ~7) == 0);
        if (if_operand_override & flags)
            i = 1;
        else
        {
            if (if_word & flags)
                i = 2;
            else
                i = 0;
        }
        put_string(reg_names[i][reg]);
    }

    static void put_displ(instruction_t &i)
    {
        objio::fixup_desc_t *f;
        unsigned char *s;

        if (i.fixkind != objio::fk_none)
        {
            if (i.fixkind == objio::fk_fixup)
            {
                f = objio::get_fixup(i.pc + i.offs);
                assert(f != NULL);
                
                if (f->target == '\1') /* symbol fixup */
                {
                    /* f->a0 = sym.kind, a1 = mnolev, a2 = adr */
                    put_string(objio::obj_info->imports[abs(f->a1)]);
                    put_string(".");
                    put_num(f->a2);
                }
                else
                {
                    switch (f->a0)
                    {
                    case objio::segUndef: s = (unsigned char *)"undef"; break;
                    case objio::segCode: s = (unsigned char *)"code"; break;
                    case objio::segConst: s = (unsigned char *)"const"; break;
                    case objio::segCase: s = (unsigned char *)"case"; break;
                    case objio::segData: s = (unsigned char *)"data"; break;
                    case objio::segExport: s = (unsigned char *)"export"; break;
                    case objio::segCommand: s = (unsigned char *)"command"; break;
                    case objio::segTypeDesc: s = (unsigned char *)"typedesc"; break;
                    default: assert(false);
                    }
                    put_string(s); put_string("."); put_num(f->a1);
                }

                if (i.disp != 0)
                {
                    put_string("+"); put_num(i.disp);
                }
            }
            else
            {
                /* A compiler helper function.   Not supported for disassembler. */
                assert(false);
            }
        }
        else
            put_num(i.disp);
    }

    static void put_seg_reg(instruction_t &i)
    {
        put_string(seg_reg_names[seg_regs_t(i.reg)]);
    }

    static void put_disp(instruction_t &i)
    {
        if (i.mr == 1 || i.mr == 2)
        {
            if (i.disp > 0)
                put_string("+");
            put_displ(i);
        }
        else if ((i.mr == 0) && ((if_scaled & i.flags) &&
                                 ((i.base == 5) || (i.rm == 5)))) { /* disp32 */
            if (i.disp > 0)
                put_string("+");
            put_displ(i);
        }
    }

    static void put_index(instruction_t &i, int s)
    {
        if (i.index != 4) /* no index */
        {
            put_string("+(");
            put_num(s);
            put_string("*");
            put_reg(i.index, if_word);
            put_string(")");
        }
    }

    static void put_mem(instruction_t &i)
    {
        int s;
        const char *mem;
        
        if (i.mr == 3)
        {
            put_reg(i.rm, i.flags);
        }
        else
        {
            if (i.memacc != maNone)
            {
                switch(i.memacc)
                {
                case maByte:  mem = "byte"; break;
                case maWord:  mem = "word"; break;
                case maDWord:  mem = "dword"; break;
                case maReal4:  mem = "real4"; break;
                case maReal8:  mem = "real8"; break;
                case maReal10: mem = "real10"; break;
                default: mem = "byte"; break; // Invalid encoding; cheat.
                }
                put_string(mem);
                put_string(" ptr ");
            }

            if (if_scaled & i.flags)
            {
                switch (inst.ss)
                {
                case 0: s = 1; break;
                case 1: s = 2; break;
                case 2: s = 4; break;
                default: s = 8; break;
                }

                put_string("[");
                switch (i.mr)
                {
                case 0:
                    if (i.base == 5) /* d32 + index */
                    {
                        put_index(i, s);
                        put_disp(i);
                    }
                    else
                    {
                        put_reg(i.base, if_word);
                        put_index(i, s);
                        put_disp(i);
                    }
                    break;

                case 1:
                case 2:
                    put_reg(i.base, if_word);
                    put_index(i, s);
                    put_disp(i);
                    break;
                }
                put_string("]");
            }
            else
            {
                if ((i.mr == 0) && (i.rm == 5))
                {
                    put_string("[");
                    put_disp(i);
                    put_string("]");
                }
                else
                {
                    put_string("[");
                    put_reg(i.rm, if_word);
                    put_disp(i);
                    put_string("]");
                }
            }
        }
    }

    static void put_inst(instruction_t &i)
    {
        const int MneCol = 40;
        const int OpCol = MneCol + 8;
        int len;

        len = 0;
      
        put_pc(i, len);
        put_bytes(i, len);
      
        if (if_label & i.flags)
            put_label(i, len);
      
        put_pad(MneCol - len);
        fprintf(fp, "%s ", mne_table[i.mne]);
        put_pad(OpCol - (MneCol + strlen(mne_table[i.mne])));

        if (i.opcl == oc_reg)
            put_reg(i.reg, i.flags);
        else if (i.opcl == oc_orm)
        {
        }
    }

    static void set_mem_acc(instruction_t i, memory_access_t ma)
    {
        if (if_operand_override & i.flags)
            i.memacc = maWord;
        else
            i.memacc = ma;
    }


    static void dEnter(void)
    {
        inst.disp = get_int_16();
        inst.data = get_int_8();
        inst.flags |= (if_data | if_disp);
        inst.opcl = oc_enter;
        put_inst(inst);
        put_num(inst.disp);
        put_string(", ");
        put_num(inst.data);
    }

    static void dOAD(void)
    {
        if (curr_decode->W)
            inst.flags |= if_word;
        
        get_immed();
        put_inst(inst);
        put_reg(0 /* EAX */, inst.flags);
        put_string(", ");
        put_num(inst.data);
    }

    static void orm_flags(void)
    {
        if (curr_decode->D)
            inst.flags |= if_direction;

        if (curr_decode->W)
            inst.flags |= if_word;
    }

    static void dORM(void)
    {
        get_mod_reg_rm();
        set_mem_acc(inst, curr_decode->MA);
        switch (inst.B0)
        {
        case 0: case 1: case 2: case 3: /* ADD */ orm_flags(); break;
        case 0xf: /* imul, movsx, movzx, setcc (2 byte inst) */
        {
            switch (inst.B1)
            {
            case 0x90: case 0x91: case 0x92: case 0x93: case 0x94: case 0x95: case 0x96: case 0x97:
            case 0x98: case 0x99: case 0x9a: case 0x9b: case 0x9c: case 0x9d: case 0x9e: case 0x9f: /* SETcc */ break;
            case 0xaf: /* IMUL */ break;
            case 0xb6: case 0xb7: /* MOVZX */ orm_flags(); break;
            case 0xbe: /* MOVSX */ orm_flags(); break;
            case 0xbf: /* MOVSX */ orm_flags(); break;
            }
            break;
        }
        case 8: case 9: case 0xa: case 0xb: /* OR */ orm_flags(); break;
        case 0x20: case 0x21: case 0x22: case 0x23: /* AND */ orm_flags(); break;
        case 0x28: case 0x29: case 0x2a: case 0x2b: /* SUB */ orm_flags(); break;
        case 0x30: case 0x31: case 0x32: case 0x33: /* XOR */ orm_flags(); break;
        case 0x38: case 0x39: case 0x3a: case 0x3b: /* CMP */ orm_flags(); break;
        case 0x84: case 0x85: case 0x86: case 0x87: /* TEST */ orm_flags(); break;
        case 0x88: case 0x89: case 0x8a: case 0x8b: /* MOV */ orm_flags(); break;
        case 0x8d: /* LEA */ orm_flags(); break;
        }

        put_inst(inst);
        if (curr_decode->D)
        {
            put_reg(inst.reg, inst.flags);
            put_string(", ");
            put_mem(inst);
        }
        else
        {
            put_mem(inst);
            put_string(", ");
            put_reg(inst.reg, inst.flags);
        }
    }

    static void omd_flags()
    {
        if (curr_decode->W)
            inst.flags |= if_word;
        if (curr_decode->S)
            inst.flags |= if_sign_extend;
    }
    
    static void dOMD(void)
    {
        mnemonic_t mne;

        get_mod_reg_rm();
        switch (inst.reg)
        {
        case 0: mne = mADD; omd_flags(); break;
        case 1: mne = mOR; omd_flags(); break;
        case 2: mne = mUNSUP; /* ADC */ omd_flags(); break;
        case 3: mne = mUNSUP; /* SBB */ omd_flags(); break;
        case 4: mne = mAND; omd_flags(); break;
        case 5: mne = mSUB; omd_flags(); break;
        case 6: mne = mXOR; omd_flags(); break;
        case 7: mne = mCMP; omd_flags(); break;
        default: mne = mCMP; break; // Invalid encoding; cheat and pretend CMP.
        }
        get_immed();
        inst.mne = mne;
        put_inst(inst);
        put_mem(inst);
        put_string(", ");
        put_num(inst.data);
    }

    static void dMOVnX(void)
    {
        instruction_flags_t flags = inst.flags;

        inst.flags = if_word;
        get_mod_reg_rm();
        inst.flags = flags;
        
        set_mem_acc(inst, curr_decode->MA);
        
        if (!(if_operand_override & inst.flags))
            inst.flags |= if_word;

        put_inst(inst);
        put_reg(inst.reg, inst.flags);
        put_string(", ");

        if (inst.B1 & 1)
            inst.flags |= if_operand_override;
        put_mem(inst);
    }

    static void dBound(void)
    {
        get_mod_reg_rm();
        inst.flags |= if_word;
        put_inst(inst);
        put_reg(inst.reg, inst.flags);
        put_string(", ");
        put_mem(inst);
    }
  
    static void dBT(void)
    {
        get_mod_reg_rm();

        switch (inst.B1)
        {
        case 0xba:
        {
            switch (inst.reg)
            {
            case 4: inst.mne = mBT; break;
            case 5: inst.mne = mBTS; break;
            case 6: inst.mne = mBTR; break;
            case 7: inst.mne = mBTC; break;
            }
            inst.data = get_int_8();
            inst.flags |= if_data;
            put_inst(inst);
            if (inst.mr == 3)
                put_reg(inst.rm, inst.flags);
            else
                put_mem(inst);
            put_string(", ");
            put_num(inst.data);
            break;
        }

        case 0xa3: case 0xa4: case 0xa5: case 0xa6: case 0xa7:
        case 0xa8: case 0xa9: case 0xaa: case 0xab:
            put_inst(inst);
            put_mem(inst);
            put_string(", ");
            put_reg(inst.reg, inst.flags);
            break;
        }
    }

    static void dOD(void)
    {
        inst.flags |= if_data;
        if (if_dual_byte & inst.flags)
        {
            switch (inst.B1)
            {
            case 0x80: case 0x81: case 0x82: case 0x83: case 0x84: case 0x85: case 0x86: case 0x87:
            case 0x88: case 0x89: case 0x8a: case 0x8b: case 0x8c: case 0x8d: case 0x8e: case 0x8f: /* Jcc */
                inst.data = get_int_32();
                inst.data += pc;
                break;
            }
        }
        else
        {
            switch (inst.B0)
            {
            case 0x68: /* PUSH */ inst.data = get_int_32(); break;
            case 0x6a: /* PUSH */ inst.data = get_int_8(); /* unsupported by code generator */ break;
            case 0x70: case 0x71: case 0x72: case 0x73: case 0x74: case 0x75: case 0x76: case 0x77:
            case 0x78: case 0x79: case 0x7a: case 0x7b: case 0x7c: case 0x7d: case 0x7e: case 0x7f: /* Jcc */
                inst.data = get_int_8();
                inst.data += pc;
                break;
            
            case 0xc2: /* RET */ inst.data = get_int_16(); break;
            case 0xcd: /* INT */ inst.data = get_int_8(); break;
            case 0xe0: case 0xe1: case 0xe2: /* LOOP */ inst.data = get_int_8(); break;
            case 0xe8: /* CALL */ inst.data = get_int_32(); break;
            case 0xe9: /* JMP */ inst.data = get_int_32(); inst.data += pc; break;
            case 0xeb: /* JMP */ inst.data = get_int_8(); inst.data += pc; break;
            }
        }
        put_inst(inst);
        put_num(inst.data);
    }


    static void dSETCC(void)
    {
        get_mod_reg_rm();
        put_inst(inst);
        put_mem(inst);
    }

    static void dOM(void)
    {
        get_mod_reg_rm();
        put_inst(inst);
        inst.memacc = curr_decode->MA;
        put_mem(inst);
    }

    static void dOpcode(void)
    {
        if (if_dual_byte & inst.flags)
        {
            switch (inst.B1)
            {
            case 0xa0: case 0xa1: put_inst(inst); put_string(seg_reg_names[srFS]); break;
            case 0xa8: case 0xa9: put_inst(inst); put_string(seg_reg_names[srGS]); break;
            }
        }
        else
        {
            switch (inst.B0)
            {
            case 0x6: case 0x7: put_inst(inst); put_string(seg_reg_names[srES]); break;
            case 0xE: put_inst(inst); put_string(seg_reg_names[srCS]); break;
            case 0x16: case 0x17: put_inst(inst); put_string(seg_reg_names[srSS]); break;
            case 0x1E: case 0x1F: put_inst(inst); put_string(seg_reg_names[srDS]); break;

            case 0x40: case 0x41: case 0x42: case 0x43: case 0x44: case 0x45: case 0x46: case 0x47: /* INC */
                put_inst(inst); put_reg(inst.B0 - 0x40, if_word);
                break;

            case 0x48: case 0x49: case 0x4a: case 0x4b: case 0x4c: case 0x4d: case 0x4e: case 0x4f: /* DEC */
                put_inst(inst); put_reg(inst.B0 - 0x48, if_word);
                break;

            case 0x50: case 0x51: case 0x52: case 0x53: case 0x54: case 0x55: case 0x56: case 0x57:  /* PUSH */
                put_inst(inst); put_reg(inst.B0 - 0x50, if_word);
                break;

            case 0x58: case 0x59: case 0x5a: case 0x5b: case 0x5c: case 0x5d: case 0x5e: case 0x5f: /* POP */
                put_inst(inst); put_reg(inst.B0 - 0x58, if_word);
                break;

            case 0x60: /* PUSHA */ put_inst(inst); break;
            case 0x61: /* POPA */ put_inst(inst); break;
            case 0x9F: /* LAHF */ put_inst(inst); break;
            case 0x90: /* NOP */ put_inst(inst); break;
            case 0x98: /* CBW -- does not handle override XXX */ put_inst(inst); break;
            case 0x99: /* CBW -- does not handle override XXX */ put_inst(inst); break;
            case 0x9B: /* WAIT */ put_inst(inst); break;
            case 0xA4: case 0xA5: /* MOVS */ put_inst(inst); break;
            case 0xA6: case 0xA7: /* CMPS */ put_inst(inst); break;
            case 0xAA: case 0xAB: /* STDS */ put_inst(inst); break;
            case 0xAC: case 0xAD: /* LODS */ put_inst(inst); break;
            case 0xAE: case 0xAF: /* SCAS */ put_inst(inst); break;
            case 0xC3: case 0xCB: /* RET, RETF */ put_inst(inst); break;
            case 0xC9: /* LEAVE */ put_inst(inst); break;
            case 0xCC: /* INT3 */ put_inst(inst); break;
            case 0xCE: /* INTO */ put_inst(inst); break;
            case 0xCF: /* IRET */ put_inst(inst); break;
            case 0xF2: /* REPNE */ put_inst(inst); break;
            case 0xF3: /* REPE */ put_inst(inst); break;
            case 0xFC: /* CLD */ put_inst(inst); break;
            case 0xFD: /* STD */ put_inst(inst); break;
            }
        }
    }

    static void dGRP5(void)
    {
        mnemonic_t mne;
        get_mod_reg_rm();
        mne = mUNSUP;

        switch (inst.reg)
        {
        case 0: mne = mINC; break;
        case 1: mne = mDEC; break;
        case 2: case 3: mne = mCALL; break;
        case 4: case 5: mne = mJMP; break;
        case 6: mne = mPUSH; break;
        }

        inst.mne = mne;
        put_inst(inst);
        if (if_operand_override & inst.flags)
            inst.memacc = maWord;
        else if (inst.B0 & 1)
            inst.memacc = maDWord;
        else
            inst.memacc = maByte;
        put_mem(inst);
    }

    static void dGRP3(void)
    {
        get_mod_reg_rm();
        if (curr_decode->W)
            inst.flags |= if_word;

        switch (inst.reg)
        {
        case 0: case 1: /* is Intel opcode table correct? two nnn-s? */ inst.mne = mTEST; get_immed(); break;
        case 2: inst.mne = mNOT; break;
        case 3: inst.mne = mNEG; break;
        case 4: inst.mne = mUNSUP; /* DIV */ break;
        case 5: inst.mne = mIMUL; break;
        case 6: inst.mne = mUNSUP; /* MUL */ break;
        case 7: inst.mne = mIDIV; break;
        }

        put_inst(inst);
        put_mem(inst);
        if (if_data & inst.flags)
        {
            put_string(", ");
            put_num(inst.data);
        }
    }

    static void dMOV(void)
    {
        inst.flags |= if_data;

        switch (inst.B0)
        {
        case 0xc6: case 0xc7:
            get_mod_reg_rm();

            if (curr_decode->W)
                inst.flags |= if_word;

            get_immed();
            put_inst(inst);
            put_mem(inst);
            put_string(", ");
            put_num(inst.data);
            break;

        case 0xb0: case 0xb1: case 0xb2: case 0xb3: case 0xb4: case 0xb5: case 0xb6: case 0xb7:
        case 0xb8: case 0xb9: case 0xba: case 0xbb: case 0xbc: case 0xbd: case 0xbe: case 0xbf:
            if (curr_decode->W)
                inst.flags |= if_word;
            get_immed();
            put_inst(inst);
            put_reg(inst.B0 & 0x7, inst.flags);
            put_string(", ");
            put_num(inst.data);
            break;

        case 0x8c:
            get_mod_reg_rm();
            put_inst(inst);
            put_mem(inst);
            put_string(", ");
            put_seg_reg(inst);
            break;

        case 0x8e:
            get_mod_reg_rm();
            put_inst(inst);
            put_seg_reg(inst);
            put_string(", ");
            put_mem(inst);
            break;
        }
    }

    static void dOAO(void)
    {
        get_displ(32, inst.disp, inst.flags, inst.fixkind);
        if (curr_decode->W)
            inst.flags |= if_word;

        put_inst(inst);
        switch (inst.B0)
        {
        case 0xa0: case 0xa1:
            put_reg(0 /* eax */, inst.flags);
            put_string(", ["); put_displ(inst); put_string("]");
            break;
            
        case 0xa2: case 0xa3:
            put_string("["); put_num(inst.disp); put_string("], ");
            put_reg(0 /* eax */, inst.flags);
            break;
        }
    }

    static void dORMD(void)
    {
        if (!(if_operand_override & inst.flags))
            inst.flags |= if_word;

        get_mod_reg_rm();
        if (curr_decode->S)
            inst.flags |= if_sign_extend;

        get_immed();
        put_inst(inst);
        put_reg(inst.reg, inst.flags);
        put_string(", ");
        put_mem(inst);
        put_string(", ");
        put_num(inst.data);
    }
    
    static void dIO(void)
    {
        if (curr_decode->W)
            inst.flags |= if_word;

        switch (inst.B0)
        {
        case 0xe4: case 0xe5: case 0xe6: case 0xe7:
            inst.data = get_int_8();
            inst.flags |= if_data;
            break;
        }
        put_inst(inst); put_reg(0 /* eax */, inst.flags);
        put_string(", ");
        if (if_data & inst.flags)
            put_num(inst.data);
        else
            put_reg(2 /* dx */, if_operand_override | if_word);
    }

    static void dSHIFT(void)
    {
        mnemonic_t mne = mUNSUP;
        get_mod_reg_rm();

        switch (inst.reg)
        {
        case 0: mne = mROL; break;
        case 1: mne = mROR; break;
        case 2: mne = mRCL; break;
        case 3: mne = mRCR; break;
        case 4: mne = mSHL; break;
        case 5: mne = mSHR; break;
        case 6: mne = mUNSUP; /* not defined */ break;
        case 7: mne = mSAR; break;
        }

        if (!(if_operand_override && inst.flags) && (inst.B0 & 1))
            inst.flags |= if_word;

        inst.mne = mne; put_inst(inst); put_mem(inst); put_string(", ");

        switch (inst.B0)
        {
        case 0xc0: case 0xc1: inst.data = get_int_8(); inst.flags |= if_data;  put_num(inst.data); break;
        case 0xd0: case 0xd1: put_num(1); break;
        case 0xd2: case 0xd3: put_reg(1 /* cl */, if_none); break;
        }
    }

    static void dFPU(void)
    {
        int dest, src, b1, b2, opa, opb, op, mf, i;
        mnemonic_t mne;
        bool d, p;

        inst.B1 = next_byte();
        b1 = inst.B0 & 7;
        b2 = (inst.B1 & 0xe0) >> 5;

        if ((b1 == 3) && (b2 == 7)) /* encoding 5 op = ORD(inst.B1) AND $1F;*/
        {
            switch (inst.B1 & 0x1f) /* op field */
            {
            case 3: mne = mFINIT; break;
            default: mne = mUNSUPFPU;
            }
            inst.mne = mne;
            put_inst(inst);
        }
        else if ((b1 == 1) && (b2 == 7)) /* encoding 4 */
        {
            op = inst.B1 & 0x1f; mne = mUNSUP;

            switch (op)
            {
            case 0x0: mne = mFCHS; break;
            case 0x1: mne = mFABS; break;
            case 0x8: mne = mFLD1; break;
            case 0xA: mne = mFLDL2E; break;
            case 0xB: mne = mFLDPI; break;
            case 0xE: mne = mFLDZ; break;
            case 0x10: mne = mF2XM1; break;
            case 0x11: mne = mFYL2X; break;
            case 0x13: mne = mFPATAN; break;
            case 0x1A: mne = mFSQRT; break;
            case 0x1C: mne = mFRNDINT; break;
            case 0x1D: mne = mFSCALE; break;
            case 0x1E: mne = mFSIN; break;
            case 0x1F: mne = mFCOS; break;
            default: assert(false);
            }
            inst.mne = mne;
            put_inst(inst);
        }
        else if ((b2 == 6) || (((b1 ^ 3) != 0) && (b2 == 7))) { /* FDIV */ /* encoding 3 */
            b1 = inst.B0; b2 = inst.B1;
            d = ((b1 >> 2) && 1) == 1;
            p = ((b1 >> 1) && 1) == 1;
            opa = b1 && 1;
            opb = (b2 >> 3) && 7;
            i = b2 && 7;

            switch (opa * 8 + opb)
            {
            case 1 * 8 + 0: /* fld */ mne = mFLD; assert(!d); assert(!p); break;
            case 0 * 8 + 1: /* fmul */ mne = mFMUL; break;
            case 0 * 8 + 6: /* fdivr */ mne = mFDIVR; break;
            case 0 * 8 + 7: /* fdiv */ mne = mFDIV; break;
            case 0 * 8 + 0: /* fadd */ mne = mFADD; break;
            case 0 * 8 + 4: /* fsubr */ mne = mFSUBR; break;
            case 0 * 8 + 5: /* fsub */ mne = mFSUB; break;
            case 0 * 8 + 2: /* fcom */ mne = mFCOM; break;
            case 0 * 8 + 3: /* fcomp/fcompp */ mne = mFCOMP; break;
            case 1 * 8 + 2: /* fst */ mne = mFST; break;
            case 1 * 8 + 3: /* fstp */ mne = mFSTP; break;
            case 1 * 8 + 4:
                mne = mFNSTSW; p = false; d = false; /* decoding is wrong; outputs st(0), st(0) as operands */ break;
            case 1 * 8 + 1:
                mne = mFXCH; p = false; d = false; /* decoding is wrong; outputs st(0), st(0) as operands */ break;
            default: mne = mUNSUP;
            }

            if (p)
                mne = static_cast<mnemonic_t>(static_cast<int>(mne) + 1); /* pop instruction */
            inst.mne = mne; put_inst(inst);

            if (d) { dest = i; src = 0; }
            else { dest = 0; src = i; }

            put_string("st("); put_num(dest); put_string("), st("); put_num(src); put_string(")");
        }
        else if ((b1 & 1) && ((inst.B1 && 0x20) != 0)) /* encoding 1 */
        {
            decode_mod_reg_rm(inst.B1, inst.mr, inst.reg, inst.rm);
            opa = (inst.B0 >> 1) & 3;
            opb = inst.reg & 3;
            get_mem_ref(inst.mr, inst.rm, inst.ss, inst.index, inst.base, inst.disp, inst.flags);

            switch (opa * 4 + opb)
            {
            case 0 * 4 + 1: mne = mFLDCW; break;
            case 1 * 4 + 1: mne = mFLD; /* 80-bit */ break;
            case 3 * 4 + 1: mne = mFILD; break;
            case 1 * 4 + 2: mne = mFST; /* 80 bit */ break;
            case 1 * 4 + 3: mne = mFSTP; /* 80bit */ break;
            case 3 * 4 + 3: mne = mFISTP; break;
            default: mne = mUNSUP;
            }

            inst.mne = mne; put_inst(inst); put_mem(inst);
        }
        else
        { /* encoding 2 */
            mne = mUNSUP; decode_mod_reg_rm(inst.B1, inst.mr, inst.reg, inst.rm);
            opa = (inst.B0 & 1);
            opb = inst.reg;
            mf = (inst.B0 >> 1) & 3;
            get_mem_ref(inst.mr, inst.rm, inst.ss, inst.index, inst.base, inst.disp, inst.flags);

            switch (opa * 8 + opb)
            {
            case 0 * 8 + 0: mne = mFADD; break;
            case 0 * 8 + 1: mne = mFMUL; break;
            case 0 * 8 + 2: mne = mFCOM; break;
            case 0 * 8 + 3: mne = mFCOMP; break;
            case 0 * 8 + 4: mne = mFSUB; break;
            case 0 * 8 + 5: mne = mFSUBR; break;
            case 0 * 8 + 6: mne = mFDIV; break;
            case 0 * 8 + 7: mne = mFDIVR; break;
            case 1 * 8 + 0:
                if (mf & 1)
                    mne = mFILD;
                else
                    mne = mFLD;
                break;

            case 1 * 8 + 2: case 1 * 8 + 3:
                if (mf & 1)
                    mne = mFIST;
                else
                    mne = mFST;

                if (opb & 1)
                    mne = static_cast<mnemonic_t>(static_cast<int>(mne) + 1); /* pop instruction */
                break;
            }

            switch (mf)
            {
            case 0: inst.memacc = maReal4; break;
            case 1: inst.memacc = maDWord; break;
            case 2: inst.memacc = maReal8; break;
            case 3: inst.memacc = maWord; break;
            }
            inst.mne = mne;
            put_inst(inst); put_mem(inst);
        }
    }


    void disassemble(FILE *fp, unsigned char *code, int offs, int len)
    {
        assert(sizeof(byte) == 1);
        assert(sizeof(short) == 2);
        assert(sizeof(int) == 4);
        x86::fp = fp;

        pc_init(code, offs);

        while (pc < offs + len + 1)
        {
            default_inst(inst);

            do
            {
                inst.B0 = next_byte();
                curr_decode = &SBDT[inst.B0];
                kind = curr_decode->cls;

                if (kind == dcOPOVR)
                    inst.flags |= if_operand_override;
                else if (kind == dcADROVR)
                    inst.flags |= if_address_override;
            } while ((kind == dcOPOVR) || (kind == dcADROVR));

            if (kind == dcDDB) {
                unsigned d;
                inst.flags |= if_dual_byte;
                inst.B1 = next_byte();
                d = inst.B1 - 0x80;
                assert(d >= 0 && d < (sizeof(DBDT) / sizeof(DBDT[0])));
                curr_decode = &DBDT[d];
                kind = curr_decode->cls;
            }

            inst.mne = curr_decode->mne;

            switch (kind)
            {
            case dcUNSUP: put_inst(inst); break;
            case dcENTER: dEnter(); break;
            case dcOAD: dOAD(); break;
            case dcORM: dORM(); break;
            case dcOMD: dOMD(); break;
            case dcMOVNX:  dMOVnX(); break;
            case dcBOUND: dBound(); break;
            case dcBT: dBT(); break;
            case dcOD: dOD(); break;
            case dcOM: dOM(); break;
            case dcSETCC: dSETCC(); break;
            case dcO: dOpcode(); break;
            case dcGRP5: dGRP5(); break;
            case dcGRP3: dGRP3(); break;
            case dcMOV: dMOV(); break;
            case dcOAO: dOAO(); break;
            case dcORMD: dORMD(); break;
            case dcIO: dIO(); break;
            case dcSHIFT: dSHIFT(); break;
            case dcFPU: dFPU(); break;
            case dcSTRING: dOpcode(); break;
            default:
                fprintf(stderr, "Unsupported opcode kind '%#x' (%#x:%#x)\n", kind, inst.B0, inst.B1);
                assert(false);
            }
            fprintf(fp, "\n");
        }
    }
}
