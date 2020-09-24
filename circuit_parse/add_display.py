import re


reg_list_ = []
wire_list_ = []
def parse_reg_name():
    reg_list = []
    wire_list = []
    print("========================parse_reg_name start================================")
    with open('picorv32.v', "r") as reader:
        for i,line in enumerate(reader.readlines(),0):
            line = line.strip()
            
            if (re.match(" ?reg ",line) or re.match("output",line) ):
                # print(line)
                if (line.find("]") == -1):
                    # print(line)
                    if len(line.split(","))==1 or line.endswith(",") :
                        # print(line)
                        if line.find("reg") == -1 and line.find("output") is not -1 :
                            reg_list.append(line.split("output")[1].strip().replace(";","").replace(",",""))
                        
                        elif(line.split("reg")[1].strip().replace(";","").find("=") ==- 1):
                            reg_list.append(line.split("reg")[1].strip().replace(";",""))

                        else:
                            
                            reg_list.append(line.split("reg")[1].strip().replace(";","").split("=")[0].strip())
                    else:
                        reg_name = line.split("reg")[1].strip()
                        reg_name = reg_name.split(",")
                        for reg in reg_name:
                            reg_list.append(reg.strip().replace(";",""))
                else:
                    if len(line.split(","))==1:
                        if (line.split("]")[1].strip().find("[")==-1):
                            if (line.split("]")[1].strip().find("=") == -1):
                                reg_list.append(line.split("]")[1].strip().replace(";",""))
                            else:
                                reg_list.append(line.split("]")[1].strip().replace(";","").split("=")[0].strip())
                        else:
                            reg_list.append(line.split("]")[1].strip().split("[")[0].strip().replace(";",""))
                    else:
                        reg_name = line.split("]")[1].strip()
                        reg_name = reg_name.split(",")
                        for reg in reg_name:
                            reg_list.append(reg.strip().replace(";",""))  
            elif (re.match(" ?wire ",line)):
                if (line.find("]") == -1):
                    if len(line.split(","))==1:
                        # print(line.split("wire")[1].strip().replace(";",""))
                        if(line.split("wire")[1].strip().replace(";","").find("=") ==- 1):
                            wire_list.append(line.split("wire")[1].strip().replace(";",""))
                        else:
                            wire_list.append(line.split("wire")[1].strip().replace(";","").split("=")[0].strip())
                    else:
                        if line.split("wire")[1].strip().find("=") is not -1:
                                wire_list.append(line.split("wire")[1].strip().split("=")[0].strip())
                        else:
                            # print(line)
                            continue
                else:
                    if len(line.split(","))==1:
                        
                        if (line.split("]")[1].strip().find("[")==-1):
                            
                            if (line.split("]")[1].strip().find("=") == -1):
                                wire_list.append(line.split("]")[1].strip().replace(";","").replace("!","").replace("&",""))
                            else:
                                wire_list.append(line.split("]")[1].strip().replace(";","").split("=")[0].strip())
                        else:
                            
                            wire_list.append(line.split("]")[1].strip().split("[")[0].strip().replace(";",""))
                    else:
                        wire_name = line.split("]")[1].strip()
                        wire_name = wire_name.split(",")
                        for reg in wire_name:
                            wire_list.append(reg.strip().replace(";","")) 
    for reg in reg_list:
        if reg != "":
            reg_list_.append(reg)
    for wire in wire_list:
        if wire != "":
            reg_list_.append(wire)
    print("========================parse_reg_name done===================================")

def parse_reg_rw():
    print("========================parse_reg_rw done===================================")
    # print(reg_list + wire_list)
    rw_list = []
    rw_dict ={}
    all_reg_list = reg_list_ + wire_list_
    all_reg_list.remove("cpuregs")
    for i in range(32):
        cpu_name = ('cpuregs[{:2}]').format(i)
        all_reg_list.append(cpu_name)
    with open('cpu_rw_2.txt', "r") as reader:
        for line in reader:
            line = line.strip()
            sim_time = line.split(" cycle ")[0].strip()
            eqn = line.split(" cycle ")[1].strip()[1:].replace("(","").replace(")","").replace("{","").replace("}","")\
            .replace(";","").replace("if","").replace("begin","").replace("assign","").replace("~","").strip()
            reg_wire_list = re.split(r"==|&&|!|&|\+|-|<<|>>|\||\|\||<=\s|==\s|=\s|,|\?|:|\|\|\s|&&\s",eqn)
            for reg in reg_wire_list:
                if reg.strip() in all_reg_list:
                    if line.find("if") is not -1:
                        print(("{} : r(ctrl) : {}").format(sim_time,reg.strip()))
                        continue
                    if line.rfind(reg.strip()) < line.find("=") and line.find("=") is not -1:
                        print(("{} : w : {}").format(sim_time,reg.strip()))
                        continue
                    elif line.rfind(reg.strip()) > line.find("=") and line.find("=") is not -1:
                        print(("{} : r : {}").format(sim_time,reg.strip()))
                        continue
                    else: 
                        continue
                else:

                    continue

    # print(all_reg_list)            
    print("========================parse_reg_rw done===================================")





def rewrite_format():
    print("========================rewrite_format start===================================")

    with open('picorv32.v', "r") as reader:
        with open ('picorv32_rewrite_format.v', "w") as writer:
            # for i,line in enumerate(reader.readlines(),0):
            
            for line in reader:

                line = line.strip()
                if (re.match(" ?if ?",line)):
                    if line.endswith("begin"):
                            writer.write(("{}\n").format(line))
                            
                    else:
                        if line.endswith(";"):
                            line = re.split(r"\) ",line)
                            writer.write(("{}) begin\n").format(line[0]))
                            writer.write(("{}\n").format(line[1]))
                            writer.write("end\n")
                            
                        elif line.endswith(")"):
                            writer.write(("{} begin\n").format(line))
                            next_line = reader.next().strip()
                            writer.write(("{} \n").format(next_line))
                            writer.write("end\n")
                        else:
                            if line.endswith(";"):
                                
                                writer.write(("{}\n").format(line))
                            elif   line.find("begin") == -1:  
                                while not(line.endswith(";")):
                                    writer.write(("{}").format(line.replace("assign","")))
                                    line = reader.next().strip()
                                writer.write(("{}\n").format(line.replace("assign","")))
                                writer.write("end\n")
                            else:
                                writer.write(("{}\n").format(line))  
                elif line.find(": ") is not -1 and line.find("?") == -1 and \
                    line.find("wire") == -1 and line.find("reg") is -1 and \
                    line.find("$") is -1 and line.find("para") is -1 and \
                    line.find("put") is -1 and line.find("+: ") is -1:
                    if line.endswith(":"):
                        writer.write(("{} begin\n").format(line))
                        next_line = reader.next().strip()
                        writer.write(("{} \n").format(next_line))
                        writer.write("end\n")
                    else:
                        
                        if  (line.find("begin")) == -1 and line.endswith(";"):
                            writer.write(("{}: begin\n").format(re.split(r"(:)",line)[0]))
                            string = ""
                            for char in re.split(r"(:)",line)[2:]:
                                string += char
                            writer.write(("{}\n").format(string))
                            writer.write("end\n")

                        else:
                            if line.endswith(";"):
                                writer.write(("{}\n").format(line))
                            elif   line.find("begin") == -1:  
                                while not(line.endswith(";")):
                                    writer.write(("{}").format(line.replace("assign","")))
                                    line = reader.next().strip()
                                writer.write(("{}\n").format(line.replace("assign","")))
                                writer.write("end\n")
                            else:
                                
                                writer.write(("{}\n").format(line))
                else:

                    if line.find("=") is not -1 and not line.endswith(";") and line.find("para") is  -1:
                        if line.endswith(";"):
                                
                                writer.write(("{}\n").format(line))
                        elif   line.find("begin") == -1  :  
                            while not(line.endswith(";")):
                                writer.write(("{}").format(line))
                                line = reader.next().strip()
                            writer.write(("{}\n").format(line))
                        else:
                            writer.write(("{}\n").format(line))  
                    elif line.endswith(":"):
                        writer.write(("{} begin\n").format(line))
                        next_line = reader.next().strip()
                        writer.write(("{} \n").format(next_line))
                        writer.write("end\n")
                    elif line.find("always") is not -1 and line.find("begin") is -1:
                        if line.endswith(";"):
                            writer.write(("{}) begin\n").format(line.split(")")[0]))
                            writer.write(("{} \n").format(line.split(")")[1]))
                            writer.write("end \n")
                        else:
                            writer.write(("{} begin\n").format(line))
                            next_line = reader.next().strip()
                            writer.write(("{} \n").format(next_line))
                            writer.write("end\n")
                    else:
                        if line.find(":") is not -1 and line.find("[") is -1 and line.find("=") is not -1 and line.find("?") is -1 :
                            writer.write(("{}: begin\n").format(line.split(":")[0]))
                            writer.write(("{} \n").format(line.split(":")[1]))
                            writer.write("end \n")
                        else:
                            writer.write(('{}\n').format(line))
    
    print("========================rewrite_format done===================================")
def add_display():
    print("========================add_display start===================================")
    with open('picorv32_rewrite_format.v', "r") as reader:
        with open ('picorv32_add_display.v', "w") as writer:
            for line in reader:
                line =line.strip()
                if  (line.find("=")) is not -1 and line.find("para") is -1 and \
                    line.find("wire") is -1 and line.find("assign") is -1\
                        and line.find("for") is -1 :
                    if line.find("if") is not -1:
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write(("{} \n").format(line))
                    elif line.find("case") is not -1 and line.find("(") is not -1:
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write(("{} \n").format(line))
                    else:
                        writer.write(("{} \n").format(line))
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                else:
                    if line.find("if") is not -1 and line.find("(") is not -1:
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write(("{} \n").format(line))
                    elif line.find("case") is not -1 and line.find("(") is not -1:
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write(("{} \n").format(line))
                    elif line.find("assign") is not -1 :
                        writer.write(("{} \n").format(line))
                        writer.write("always@* begin \n")
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write("end \n")

                    else:
                        writer.write(("{} \n").format(line))
                




    print("========================add_display done===================================")





if __name__ =="__main__":
    parse_reg_name()
    parse_reg_rw()
    # rewrite_format()
    # add_display()


    print("========================__main__ done===================================")