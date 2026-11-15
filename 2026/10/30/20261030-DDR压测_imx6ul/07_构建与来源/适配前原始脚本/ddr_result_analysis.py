import os

def get_ddr_memtester(fd):
    line="s"
    count=0
    total=0
    stuck_address = 0
    random_value = 0
    compare_xor = 0
    compare_sub = 0
    compare_or = 0
    compare_and = 0
    sequential_ncrement = 0
    solid_bits = 0
    compare_mul = 0
    block_sequential = 0
    checkerboard = 0
    bit_spread = 0
    bit_flip = 0
    walking_ones = 0
    walking_zeroes = 0
    bit8_writes = 0
    bit16_writes = 0
    while line:
        line = fd.readline()
        if "Stuck Address" in line:
            list1 = line
            total += 1
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                stuck_address+=1

        if "Random Value" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                random_value += 1

        if "Compare XOR" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                compare_xor += 1

        if "Compare SUB" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                compare_sub += 1

        if "Compare OR" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                compare_or += 1

        if "Compare AND" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                compare_and += 1

        if "Sequential Increment" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                sequential_ncrement += 1

        if "Solid Bits" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                solid_bits += 1

        if "Compare MUL" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                compare_mul += 1

        if "Block Sequential" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                block_sequential += 1

        if "Checkerboard" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                checkerboard += 1

        if "Bit Spread" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                bit_spread += 1

        if "Bit Flip" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                bit_flip += 1

        if "Walking Ones" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                walking_ones += 1

        if "Walking Zeroes" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                walking_zeroes += 1

        if "8-bit Writes" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                bit8_writes += 1

        if "16-bit Writes" in line:
            list1 = line
            list1 = list1.split(":")[1].replace(' ', '').replace('\n', '').replace('\r', '')
            if list1 == "ok":
                bit16_writes += 1

    if stuck_address==total and random_value==total and compare_xor==total and compare_sub==total and compare_or==total and compare_and==total \
            and sequential_ncrement == total and solid_bits==total and compare_mul==total and block_sequential==total and checkerboard==total and bit_spread==total \
            and bit_flip == total and walking_ones==total and walking_zeroes==total and bit8_writes==total and bit16_writes==total:
        count+=1
        print("1. total:%d, success count:%d, ddr memtester:PASS" % (total, total))
    else:
        print("1. total:%d, success count:%d, ddr memtester:FAILED")
    fd.seek(0)

def get_ddr_stressapptest(fd):
    line="s"
    count=0
    total=0
    dhy_resurt=0
    while line:
        line = fd.readline()
        if "ddr stressapptest" in line:
            list1 = line

            list1 = list1.split(":")[1].split(" ")[1]
            total += 1
            if "PASS" in list1:
                count += 1
    fd.seek(0)
    if count == total:
        print("2. total:%d, success count:%d, stressapptest result: PASS" % (total, count))
    else:
        print("2. total:%d, success count:%d, stressapptest result: FAILED" % (total, count))



def get_unpack_bin(fd):
    line="s"
    count=0
    total=0

    while line:
        line = fd.readline()
        if "unpack bin" in line:
            list1 = line

            list1 = list1.split(":")[1].split(" ")[1]
            total += 1
            if "Success" in list1:
                count += 1
    fd.seek(0)
    if count == total:
        print("3. total:%d, success count:%d, unpack bin result: Success" % (total, count))
    else:
        print("3. total:%d, success count:%d, unpack bin result: FAILED" % (total, count))

def get_unpack_tar(fd):
    line="s"
    count=0
    total=0

    while line:
        line = fd.readline()
        if "unpack tar" in line:
            list1 = line

            list1 = list1.split(":")[1].split(" ")[1]
            total += 1
            if "Success" in list1:
                count += 1
    fd.seek(0)
    if count == total:
        print("4. total:%d, success count:%d, unpack tar result: Success" % (total, count))
    else:
        print("4. total:%d, success count:%d, unpack tar result: FAILED" % (total, count))


def data_analyzer(file_name):

    fd = open(file_name)
    print("  file    name:", os.path.split(file_name)[1])

    get_ddr_memtester(fd)
    get_ddr_stressapptest(fd)
    get_unpack_bin(fd)
    get_unpack_tar(fd)


if __name__ == '__main__':
    print("-------------------data analyzer start----------------------")
    file_path = r"C:/Users/admin/Desktop/rv1126_AA30单元测试项/测试结果记录/ddr_2/2.log"

    data_analyzer(file_path)

    print("-------------------data analyzer end----------------------")
