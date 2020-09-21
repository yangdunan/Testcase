import pandas as pd

reg_list = [" irq_mask ","reg_out","reg_next_pc",
"reg_pc","timer","alu_add_sub","reg_op1","alu_out_q",
"alu_shl","alu_lts","alu_eq","irq_pending","alu_shr",
"reg_op2"]

if __name__ == "__main__":
    
    
    rw_list = []
    #add arch reg in reg_list
    for i in range(32):
        if i <10:
            arch_reg = "cpuregs[ "+str(i)+"]"
        else:
            arch_reg = "cpuregs["+str(i)+"]"
        reg_list.append(arch_reg)
        rw_dict = {}
    with open('./cpu_rw.txt','r') as f:
        lines = f.readlines()
        current_cycle = 0
        one_cycle_rw_list = []
        for line in lines:
            line = line.strip()
            print(line)
            next_cycle = line.split("cycle")[0]
            if next_cycle == current_cycle:
                rw_dict["sim_cycle"] = current_cycle
            else:
                current_cycle = next_cycle
            rw_dict["sim_cycle"] = current_cycle
            for reg_name in reg_list:
                if (len(line.split("=")) == 2):
                    lhs = line.split("=")[0]
                    rhs = line.split("=")[1]
                    if lhs.find(reg_name) !=  -1:
                        rw_dict[reg_name] = "w"
                    elif rhs.find(reg_name) !=  -1:
                        rw_dict[reg_name] = "r"
                    elif rhs.find(reg_name) !=  -1 and lhs.find(reg_name) !=  -1:
                        rw_dict[reg_name] = "rw"
                    else:
                        rw_dict[reg_name] = " "


            print(rw_dict)
            print(len(rw_dict))
            
            